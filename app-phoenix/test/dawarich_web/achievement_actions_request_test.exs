defmodule DawarichWeb.AchievementActionsRequestTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Repo
  alias Dawarich.Test.{RailsUser, RawHTTP}
  alias DawarichWeb.{RailsCsrf, RailsProxy}
  alias DawarichWeb.AchievementActions.{Gate, Request}

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

  test "admits the real JSON clients and Rails sharing form with method path CSRF" do
    session = RailsUser.session(44001)

    for key <- ~w(country_de country_fr border_hopper),
        value <- [true, false, 0, 1, "off", "false", "arbitrary"] do
      path = "/achievements/#{key}/toggle_sharing"
      raw = Jason.encode!(%{"enabled" => value})
      conn = request("PATCH", path, raw, session)
      assert Gate.eligible?(conn, :sharing)
      {:ok, loaded, actor, params, context} = accepted!(conn, :sharing)
      assert actor.id == 44001 and actor.admin == false
      assert params["enabled"] == value
      assert context.locale == "en" and context.key == key
      assert loaded.private.dawarich_raw_body == raw and loaded.method == "PATCH"
      assert loaded.resp_cookies == %{}
    end

    path = "/achievements/country_de/toggle_sharing"
    token = RailsCsrf.masked_form_token(session, path, "PATCH")

    raw =
      URI.encode_query(%{
        "_method" => "patch",
        "enabled" => "true",
        "authenticity_token" => token
      })

    conn =
      request("POST", path, raw, session, type: "application/x-www-form-urlencoded", csrf: false)

    {:ok, loaded, _, params, context} = accepted!(conn, :sharing)
    assert loaded.method == "POST" and context.method == "PATCH"
    assert params["enabled"] == "true" and context.state == %{}

    for {action, path, raw} <- [
          {:next, "/achievements/unlocks/next", "{}"},
          {:next, "/achievements/unlocks/next", ~s({"claim_token":null,"batch_end_id":null})},
          {:seen, "/achievements/unlocks/44001/seen", ~s({"claim_token":"synthetic"})},
          {:dismiss, "/achievements/unlocks/dismiss", ~s({"batch_end_id":44001})}
        ] do
      accepted!(request("POST", path, raw, session), action)
    end

    global = RailsCsrf.masked_token(session)

    accepted!(request("PATCH", path, "{}", session, token: global), :sharing)

    rejected!(request("PATCH", path, "{}", session, token: "invalid"), :sharing)

    wrong =
      RailsCsrf.masked_form_token(session, "/achievements/country_fr/toggle_sharing", "PATCH")

    rejected!(request("PATCH", path, "{}", session, token: wrong), :sharing)

    rejected!(
      request("PATCH", path, "{}", session,
        headers: [{"origin", "https://outside.example.invalid"}]
      ),
      :sharing
    )

    before = snapshot()
    raw = ~s({"locale":"de","enabled":null})
    rejected!(request("PATCH", path, raw, session), :sharing)

    Repo.query!("UPDATE users SET encrypted_password='synthetic-salt-change' WHERE id=44001", [],
      log: false
    )

    rejected!(request("PATCH", path, "{}", session), :sharing)
    assert Enum.take(snapshot(), 2) == Enum.take(before, 2)
  end

  test "replays ambiguous transport unchanged before effects" do
    session = RailsUser.session(44001)
    path = "/achievements/country_de/toggle_sharing"
    before = snapshot()

    bad = [
      {path, ~s({"enabled":false,"enabled":true}), []},
      {path, ~s({"enabled":{"nested":true}}), []},
      {path, ~s({"enabled":true,"unknown":1}), []},
      {path, ~s({"enabled":true,"_method":"patch"}), []},
      {path, ~s({"enabled":true,"locale":"de"}), [headers: [{"x-csrf-token", "second"}]]},
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
      conn = request("PATCH", target, raw, session, opts)
      rejected = rejected!(conn, :sharing)

      assert rejected.method == "PATCH" and
               rejected.query_string == (URI.parse(target).query || "")

      assert rejected.resp_cookies == %{}
      assert snapshot() == before
      replay!(rejected, target, raw)
    end

    for raw <- [
          "enabled=true&enabled=false",
          "enabled=%zz",
          "enabled%5Bnested%5D=true",
          "locale=de&locale=en"
        ] do
      conn = request("PATCH", path, raw, session, type: "application/x-www-form-urlencoded")
      rejected = rejected!(conn, :sharing)
      replay!(rejected, path, raw)
    end

    for extra <- [%{"invitation_token" => "synthetic"}, %{"dawarich_client" => "ios"}, %{}] do
      current = if extra == %{}, do: %{}, else: Map.merge(session, extra)
      rejected!(request("PATCH", path, "{}", current), :sharing)
    end

    Repo.query!("UPDATE users SET settings='[]'::jsonb WHERE id=44001", [], log: false)

    rejected = rejected!(request("PATCH", path <> "?locale=de", "{}", session), :sharing)

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
    assert line == "PATCH " <> target <> " HTTP/1.1"
    assert body == raw
    :gen_tcp.close(server.listen)
  end
end
