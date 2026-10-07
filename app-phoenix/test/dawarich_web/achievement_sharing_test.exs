defmodule DawarichWeb.AchievementSharingTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.Repo
  alias Dawarich.Test.{RailsUser, RawHTTP}
  alias DawarichWeb.{RailsCsrf, RequestURL}
  alias DawarichWeb.AchievementActions.Sharing

  @uuid "a10c0000-0000-4000-8000-000000000001"

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    RailsUser.insert!(%{
      id: 44001,
      email: "sharing-http@example.invalid",
      settings: %{"locale" => "en"}
    })

    :ok
  end

  @tag :safe_back3
  test "F1 signed sharing rejects browser backslash userinfo tricks and preserves relative returns" do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    for {referer, location} <- [
          {"http://evil.example\\@www.example.com/offer",
           "http://www.example.com/achievements/country_de"},
          {"//evil.example\\@www.example.com/offer",
           "http://www.example.com/achievements/country_de"},
          {"http://user@www.example.com/offer", "http://www.example.com/achievements/country_de"},
          {"/achievements/country_de?page=2#card",
           "http://www.example.com/achievements/country_de?page=2#card"},
          {"https://www.example.com:8443/achievements/country_de?page=2",
           "https://www.example.com:8443/achievements/country_de?page=2"}
        ] do
      response =
        request(
          "POST",
          "/achievements/country_de/toggle_sharing",
          %{"_method" => "patch", "enabled" => true},
          false,
          referer
        )
        |> DawarichWeb.Endpoint.call([])

      assert response.status == 302
      assert get_resp_header(response, "location") == [location]

      assert [[true]] =
               rows(
                 "SELECT sharing_enabled FROM achievement_progresses WHERE user_id=44001 AND achievement_key='country_de'"
               )
    end
  end

  test "answers Rails sharing form and modal JSON with exact redirects and URLs" do
    fixtures =
      Path.expand("../fixtures/achievement_actions/responses.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()

    for fixture <-
          Enum.filter(
            fixtures,
            &(&1["status"] in [200, 302] and is_binary(get_in(&1, ["before", "key"])))
          ) do
      key = fixture["before"]["key"]
      rows("DELETE FROM achievement_progresses WHERE user_id=44001")
      uuid = fixture["after"]["uuid"] || @uuid

      rows(
        "INSERT INTO achievement_progresses(user_id,achievement_key,state,sharing_enabled,sharing_uuid,created_at,updated_at) VALUES(44001,$1,$2,$3,$4,now(),now())",
        [key, fixture["before"]["state"], fixture["before"]["enabled"], uuid]
      )

      conn =
        request(
          fixture["method"],
          fixture["path"],
          fixture["params"],
          fixture["json_request"],
          fixture["referer"]
        )

      result = Sharing.call(conn, [])
      assert result.status == fixture["status"], fixture["name"]
      assert get_resp_header(result, "content-type") == [fixture["headers"]["content-type"]]
      assert get_resp_header(result, "cache-control") == [fixture["headers"]["cache-control"]]

      assert [[enabled, ^uuid, state]] =
               rows(
                 "SELECT sharing_enabled,sharing_uuid,state FROM achievement_progresses WHERE user_id=44001 AND achievement_key=$1",
                 [key]
               )

      assert enabled == fixture["after"]["enabled"] and state == fixture["before"]["state"]

      if fixture["json_request"] do
        expected = Map.put(fixture["json"], "uuid", uuid)

        expected =
          Map.put(
            expected,
            "url",
            if(enabled, do: RequestURL.base(conn) <> "/shared/achievements/" <> uuid, else: nil)
          )

        assert Jason.decode!(result.resp_body) == expected
      else
        assert result.resp_body == fixture["body"]
        assert get_resp_header(result, "location") == [fixture["location"]]
      end

      assert Map.get(result.private, :dawarich_rails_session_changes, %{}) |> Map.get("flash") ==
               nil
    end

    conn =
      request("PATCH", "/achievements/country_de/toggle_sharing", %{"enabled" => true}, true, nil)

    conn = %{conn | host: "cards.example.invalid", scheme: :https, port: 443}
    result = Sharing.call(conn, [])

    assert Jason.decode!(result.resp_body)["url"] ==
             "https://cards.example.invalid/shared/achievements/" <> @uuid

    conn =
      request(
        "PATCH",
        "/achievements/country_de/toggle_sharing",
        %{"enabled" => true},
        false,
        nil
      )
      |> put_req_header(
        "accept",
        "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      )

    result = Sharing.call(conn, [])
    assert result.status == 302 and result.resp_body == ""
  end

  @tag a12f3b_case: "A02b"
  test "does not replay after a sharing effect or response failure" do
    server = RawHTTP.listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    parent = self()

    forbidden =
      Task.async(fn ->
        socket = RawHTTP.accept(server)
        RawHTTP.read_head(socket)
        send(parent, :unexpected_upstream)
        RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 5\r\n\r\nRails")
        :gen_tcp.close(socket)
      end)

    conn = request("PATCH", "/achievements/country_de/toggle_sharing", %{}, true, nil)
    responder = fn _, _, _ -> raise "synthetic response failure" end

    result =
      Sharing.call(conn, context: %{respond: responder}, upstream: {{127, 0, 0, 1}, server.port})

    refute_received :unexpected_upstream
    Task.shutdown(forbidden, :brutal_kill)
    assert result.status == 500 and result.halted

    assert [[true, uuid]] =
             rows(
               "SELECT sharing_enabled,sharing_uuid FROM achievement_progresses WHERE user_id=44001"
             )

    assert is_binary(uuid)
    assert [[1]] = rows("SELECT count(*) FROM achievement_progresses WHERE user_id=44001")

    disabled =
      Sharing.call(
        request(
          "PATCH",
          "/achievements/country_de/toggle_sharing",
          %{"enabled" => false},
          true,
          nil
        ),
        []
      )

    assert Jason.decode!(disabled.resp_body) == %{
             "enabled" => false,
             "uuid" => uuid,
             "url" => nil
           }

    enabled =
      Sharing.call(
        request(
          "PATCH",
          "/achievements/country_de/toggle_sharing",
          %{"enabled" => true},
          true,
          nil
        ),
        []
      )

    assert Jason.decode!(enabled.resp_body)["uuid"] == uuid
    assert {:error, :timeout} = :gen_tcp.accept(server.listen, 0)

    conn =
      request(
        "PATCH",
        "/achievements/country_fr/toggle_sharing",
        %{"enabled" => nil, "locale" => "de"},
        true,
        nil
      )

    raw = conn.adapter |> elem(1) |> Map.fetch!(:req_body)

    upstream =
      Task.async(fn ->
        socket = RawHTTP.accept(server)
        {head, rest} = RawHTTP.read_head(socket)
        length = RawHTTP.header(head, "content-length") |> hd() |> String.to_integer()
        body = RawHTTP.read_at_least(socket, rest, length) |> binary_part(0, length)
        RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 5\r\n\r\nRails")
        :gen_tcp.close(socket)
        {RawHTTP.request_line(head), body}
      end)

    result = Sharing.call(conn, upstream: {{127, 0, 0, 1}, server.port})
    assert result.status == 218 and result.resp_body == "Rails"
    assert Task.await(upstream) == {"PATCH /achievements/country_fr/toggle_sharing HTTP/1.1", raw}
    assert [[1]] = rows("SELECT count(*) FROM achievement_progresses WHERE user_id=44001")
    assert [[%{"locale" => "en"}]] = rows("SELECT settings FROM users WHERE id=44001")
  end

  defp request(method, path, params, json, referer) do
    session = RailsUser.session(44001)
    effective = if params["_method"] == "patch", do: "PATCH", else: method
    token = RailsCsrf.masked_form_token(session, path, effective)
    params = Map.drop(params, ["authenticity_token"])

    raw =
      if json,
        do: Jason.encode!(params),
        else: URI.encode_query(Map.put(params, "authenticity_token", token))

    conn =
      build_conn(method, path, raw)
      |> Map.put(:host, "www.example.com")
      |> put_req_header(
        "content-type",
        if(json, do: "application/json", else: "application/x-www-form-urlencoded")
      )
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> put_req_header("accept", if(json, do: "application/json", else: "text/html"))
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    conn = if json, do: put_req_header(conn, "x-csrf-token", token), else: conn
    if referer, do: put_req_header(conn, "referer", referer), else: conn
  end

  defp rows(sql, args \\ []), do: Repo.query!(sql, args, log: false).rows
end
