defmodule DawarichWeb.Api.IngestEndpointTest do
  use Dawarich.IngestCase, async: false
  import Dawarich.Test.RawHTTP

  @moduletag :capture_log

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      System.delete_env("SELF_HOSTED")
      System.delete_env("DAWARICH_RAILS_SLICES")
    end)

    %{upstream: upstream, port: port, user: user!(%{api_key: "phoenix-a3-endpoint-key"})}
  end

  @body ~s({"locations":{"geometry":{"coordinates":[13.4,52.5]},"properties":{"timestamp":"2026-09-28T11:00:00Z"}}})

  defp post(port, path, body \\ @body) do
    client = connect(port)

    send_raw(
      client,
      "POST #{path} HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\nAuthorization: Bearer phoenix-a3-endpoint-key\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
    )

    client
  end

  defp puma(upstream) do
    socket = accept(upstream)
    {head, _rest} = read_head(socket)
    reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
    request_line(head)
  end

  test "Phoenix answers an owned batch on a self-hosted install", %{port: port} do
    assert {201, headers, ~s({"result":"ok"})} =
             port |> post("/api/v1/overland/batches") |> read_response()

    assert values(headers, "etag") != []
    assert [[1]] = Repo.query!("SELECT count(*) FROM points").rows
    assert length(commands()) == 6
  end

  for {name, env} <- [
        {"Cloud", {"SELF_HOSTED", "false"}},
        {"the kill switch", {"DAWARICH_RAILS_SLICES", "ingest"}}
      ] do
    test "#{name} keeps the route on Rails", %{port: port, upstream: upstream} do
      {var, value} = unquote(Macro.escape(env))
      System.put_env(var, value)
      client = post(port, "/api/v1/overland/batches")
      assert puma(upstream) == "POST /api/v1/overland/batches HTTP/1.1"
      assert {200, _, "rails"} = read_response(client)
    end
  end

  test "GET and .json variants stay on Rails", %{port: port, upstream: upstream} do
    client = connect(port)
    send_raw(client, "GET /api/v1/points HTTP/1.1\r\nHost: localhost\r\n\r\n")
    assert puma(upstream) == "GET /api/v1/points HTTP/1.1"
    assert {200, _, "rails"} = read_response(client)

    client = post(port, "/api/v1/points.json")
    assert puma(upstream) == "POST /api/v1/points.json HTTP/1.1"
    assert {200, _, "rails"} = read_response(client)
  end

  defp no_upstream!(upstream),
    do: assert({:error, :timeout} = :gen_tcp.accept(upstream.listen, 0))

  test "write boundary (a): a coercion failure in prepare is handed to Rails and writes nothing",
       %{port: port, upstream: upstream} do
    body =
      ~s({"locations":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"timestamp":1790000000,"battery_level":true}}]})

    client = post(port, "/api/v1/points", body)
    assert puma(upstream) == "POST /api/v1/points HTTP/1.1"
    assert {200, _, "rails"} = read_response(client)
    assert {[[0]], []} = {Repo.query!("SELECT count(*) FROM points").rows, commands()}
  end

  test "write boundary (b): a database error inside slice 1 gets Rails' 500, no hand-off, no rows",
       %{port: port, upstream: upstream} do
    Repo.query!("ALTER TABLE phoenix.rails_commands RENAME TO rails_commands_away")

    assert {500, headers, ~s({"error":"Batch creation failed"})} =
             port |> post("/api/v1/overland/batches") |> read_response()

    assert values(headers, "content-type") == ["application/json; charset=utf-8"]
    assert values(headers, "cache-control") == ["no-cache"]
    no_upstream!(upstream)
    assert [[0]] = Repo.query!("SELECT count(*) FROM points").rows
  end

  test "write boundary (c): a failure after slice 1 committed gets Rails' 500 and keeps slice 1, with no hand-off",
       %{port: port, upstream: upstream} do
    Repo.query!(
      "CREATE FUNCTION a3_counter_fault() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'a3 counter fault'; END $$"
    )

    Repo.query!(
      "CREATE TRIGGER a3_counter_fault BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION a3_counter_fault()"
    )

    for {path, body} <- [
          {"/api/v1/points", ~s({"error":"Point creation failed"})},
          {"/api/v1/owntracks/points", ~s({"error":"Point creation failed"})}
        ] do
      request =
        if path =~ "owntracks",
          do: ~s({"_type":"location","lat":52.6,"lon":13.5,"tst":1790000001}),
          else:
            ~s({"locations":[{"geometry":{"coordinates":[13.4,52.5]},"properties":{"timestamp":1790000000}}]})

      assert {500, _, ^body} = port |> post(path, request) |> read_response()
    end

    no_upstream!(upstream)
    assert [[2]] = Repo.query!("SELECT count(*) FROM points").rows
    assert ["points.tile_epoch", "points.tile_epoch"] = Enum.map(commands(), &hd/1)
  end
end
