defmodule DawarichWeb.AchievementActionsRequestTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Repo
  alias Dawarich.Test.{RailsUser, RawHTTP}
  alias DawarichWeb.{RailsCsrf, RailsProxy}
  alias DawarichWeb.AchievementActions.{Request}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 44001,
      email: "a10c-request@example.invalid",
      admin: false,
      status: 0,
      plan: 0,
      active_until: ~N[2020-01-01 00:00:00],
      settings: %{"locale" => "en", "timezone" => "Europe/Berlin"}
    })

    :ok
  end

  test "native achievement values persist while retained deck JSON enforces method path CSRF" do
    session = RailsUser.session(44001)

    user = Dawarich.Accounts.get(44001)

    for key <- ~w(country_de country_fr border_hopper),
        value <- [true, false, 0, 1, "off", "false", "arbitrary"] do
      assert {:ok, result} =
               Dawarich.Sharing.change(
                 Dawarich.Accounts.Scope.for_user(user, "en"),
                 %{type: :achievement, key: key, owner_id: user.id},
                 :update,
                 %{"enabled" => value}
               )

      assert result.enabled == Dawarich.Families.SharingUpdate.Web.boolean(value)

      assert [[enabled]] =
               Repo.query!(
                 "SELECT sharing_enabled FROM achievement_progresses WHERE user_id=$1 AND achievement_key=$2",
                 [user.id, key],
                 log: false
               ).rows

      assert enabled == result.enabled
    end

    for {action, path, raw} <- [
          {:next, "/achievements/unlocks/next", "{}"},
          {:next, "/achievements/unlocks/next", ~s({"claim_token":null,"batch_end_id":null})},
          {:seen, "/achievements/unlocks/44001/seen", ~s({"claim_token":"synthetic"})},
          {:dismiss, "/achievements/unlocks/dismiss", ~s({"batch_end_id":44001})}
        ] do
      accepted!(request("POST", path, raw, session), action)
    end

    path = "/achievements/unlocks/next"
    global = RailsCsrf.masked_token(session)

    accepted!(request("POST", path, "{}", session, token: global), :next)

    rejected!(request("POST", path, "{}", session, token: "invalid"), :next)

    wrong =
      RailsCsrf.masked_form_token(session, "/achievements/unlocks/dismiss", "POST")

    rejected!(request("POST", path, "{}", session, token: wrong), :next)

    rejected!(
      request("POST", path, "{}", session,
        headers: [{"origin", "https://outside.example.invalid"}]
      ),
      :next
    )

    before = snapshot()
    raw = ~s({"locale":"de","claim_token":{}})
    rejected!(request("POST", path, raw, session), :next)

    Repo.query!("UPDATE users SET encrypted_password='synthetic-salt-change' WHERE id=44001", [],
      log: false
    )

    rejected!(request("POST", path, "{}", session), :next)
    assert Enum.take(snapshot(), 2) == Enum.take(before, 2)
  end

  test "retained deck JSON replays ambiguous transport unchanged before effects" do
    session = RailsUser.session(44001)
    path = "/achievements/unlocks/next"
    before = snapshot()

    bad = [
      {path, ~s({"claim_token":false,"claim_token":true}), []},
      {path, ~s({"claim_token":{"nested":true}}), []},
      {path, ~s({"claim_token":true,"unknown":1}), []},
      {path, ~s({"claim_token":true,"_method":"patch"}), []},
      {path, ~s({"claim_token":true,"locale":"de"}), [headers: [{"x-csrf-token", "second"}]]},
      {path, "{", []},
      {path, <<255>>, []},
      {path <> "?locale=de&locale=en", "{}", []},
      {path <> "?locale=de", ~s({"locale":"en"}), []},
      {path <> "?locale=%zz", "{}", []},
      {path <> ".json", "{}", []},
      {path, "{}", [headers: [{"x-http-method-override", "PATCH"}]]},
      {path, "{}", [headers: [{"x-dawarich-client", "ios"}]]},
      {path, "{}", [type: "multipart/form-data;boundary=test"]},
      {path, "{}", [headers: [{"transfer-encoding", "chunked"}]]},
      {path, String.duplicate("x", 65_537), []}
    ]

    for {target, raw, opts} <- bad do
      conn = request("POST", target, raw, session, opts)
      rejected = rejected!(conn, :next)

      assert rejected.method == "POST" and
               rejected.query_string == (URI.parse(target).query || "")

      assert rejected.resp_cookies == %{}
      assert snapshot() == before
      replay!(rejected, target, raw)
    end

    for raw <- [
          "claim_token=true&claim_token=false",
          "claim_token=%zz",
          "claim_token%5Bnested%5D=true",
          "locale=de&locale=en"
        ] do
      conn = request("POST", path, raw, session, type: "application/x-www-form-urlencoded")
      rejected = rejected!(conn, :next)
      replay!(rejected, path, raw)
    end

    for extra <- [%{"invitation_token" => "synthetic"}, %{"dawarich_client" => "ios"}, %{}] do
      current = if extra == %{}, do: %{}, else: Map.merge(session, extra)
      rejected!(request("POST", path, "{}", current), :next)
    end

    Repo.query!("UPDATE users SET settings='[]'::jsonb WHERE id=44001", [], log: false)

    rejected = rejected!(request("POST", path <> "?locale=de", "{}", session), :next)

    assert rejected.resp_cookies == %{}
    assert Repo.query!("SELECT settings FROM users WHERE id=44001", [], log: false).rows == [[[]]]
  end

  defp accepted!(conn, action) do
    result = Request.load(conn, action)
    assert elem(result, 0) == :ok, "supported request handed back"
    result
  end

  defp rejected!(conn, action) do
    result = Request.load(conn, action)
    assert elem(result, 0) == :handoff, "unsupported request admitted"
    elem(result, 1)
  end

  defp request(method, path, raw, session, opts \\ []) do
    type = Keyword.get(opts, :type, "application/json")
    effective = if method == "POST" and raw =~ "_method=patch", do: "PATCH", else: method

    token =
      Keyword.get_lazy(opts, :token, fn ->
        RailsCsrf.masked_form_token(session, URI.parse(path).path, effective)
      end)

    conn =
      build_conn(method, path, raw)
      |> put_req_header("content-type", type)
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> put_req_header(
        "accept",
        if(type == "application/x-www-form-urlencoded", do: "text/html", else: "application/json")
      )
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    conn =
      if Keyword.get(opts, :csrf, true) and token,
        do: put_req_header(conn, "x-csrf-token", token),
        else: conn

    %{conn | req_headers: conn.req_headers ++ Keyword.get(opts, :headers, [])}
  end

  defp snapshot do
    for table <- ~w(achievement_progresses achievement_unlock_events users) do
      Repo.query!("SELECT to_jsonb(t) FROM #{table} t ORDER BY to_jsonb(t)::text", [], log: false).rows
    end
  end

  defp replay!(conn, target, raw) do
    server = RawHTTP.listen()

    task =
      Task.async(fn ->
        socket = RawHTTP.accept(server)
        {head, rest} = RawHTTP.read_head(socket)
        length = RawHTTP.header(head, "content-length") |> List.first("0") |> String.to_integer()

        body =
          if RawHTTP.header(head, "transfer-encoding") == ["chunked"],
            do: RawHTTP.dechunk(socket, rest),
            else: RawHTTP.read_at_least(socket, rest, length) |> binary_part(0, length)

        RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 5\r\n\r\nRails")
        :gen_tcp.close(socket)
        {RawHTTP.request_line(head), body}
      end)

    proxied = RailsProxy.call(conn, {{127, 0, 0, 1}, server.port})
    assert proxied.status == 218 and proxied.resp_body == "Rails"
    {line, body} = Task.await(task)
    assert line == "POST " <> target <> " HTTP/1.1"
    assert body == raw
    :gen_tcp.close(server.listen)
  end
end
