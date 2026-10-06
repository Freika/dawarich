defmodule DawarichWeb.A12f2JClosureTest do
  use Dawarich.ApiEndpointCase

  @moduletag :capture_log
  @key "a12f2-j-synthetic-api-key"

  @tag :a12f2_j_activate_b
  test "Merged photos places and search handlers are reachable through the real Endpoint", c do
    for {method, path} <- [
          {"GET", "/api/v1/photos"},
          {"GET", "/api/v1/locations/suggestions"},
          {"GET", "/api/v1/places/nearby"},
          {"GET", "/api/v1/places/search"},
          {"POST", "/api/v1/immich/enrich/scan"},
          {"POST", "/api/v1/immich/enrich"}
        ] do
      assert {401, _, ""} = endpoint(c, method, path), path
    end

    user!(%{api_key: @key, settings: %{"timezone" => "UTC"}})
    assert {200, _, body} = endpoint(c, "GET", "/api/v1/locations/suggestions", bearer())
    assert is_map(Jason.decode!(body))

    for {path, action} <- [
          {"/api/v1/locations", :index_closure},
          {"/api/v1/photos/photo/thumbnail", :thumbnail_closure},
          {"/api/v1/places", {:closure, :index}}
        ] do
      assert route("GET", path).plug_opts == action
    end

    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_activate_c
  test "Merged spatial tiles digest and MCP reads own their Endpoint requests", c do
    for path <-
          ~w(/api/v1/timeline /api/v1/tags/privacy_zones /api/v1/countries/borders /api/v1/countries/visited /api/v1/points/tracked_months /api/v1/maps/hexagons /api/v1/maps/hexagons/bounds /api/v1/maps/hexagons/fog /api/v1/tiles/points/0/0/0.mvt /api/v1/tiles/tracks/0/0/0.mvt /api/v1/mcp) do
      assert {401, _, ""} = endpoint(c, "GET", path), path
    end

    user!(%{api_key: @key, settings: %{"timezone" => "UTC"}})

    assert {200, _, timeline} =
             endpoint(
               c,
               "GET",
               "/api/v1/timeline?start_at=2026-01-01&end_at=2026-01-01",
               bearer()
             )

    assert is_map(Jason.decode!(timeline))
    assert {204, _, ""} = endpoint(c, "GET", "/api/v1/tiles/points/0/0/0.mvt", bearer())

    assert {404, _, _} =
             endpoint(c, "GET", "/api/v1/maps/hexagons?uuid=missing", [
               {"Accept", "application/json"}
             ])

    assert route("GET", "/api/v1/digests").plug_opts == :closure_index
    assert route("GET", "/api/v1/digests/2026").plug_opts == :closure_show

    for method <- ~w(GET POST DELETE),
        do: assert(route(method, "/api/v1/mcp").plug_opts == :handle)

    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_activate_e
  test "Merged imports pending intake and point mutations own native Endpoint admission", c do
    for {method, path} <- [
          {"GET", "/api/v1/imports"},
          {"GET", "/api/v1/imports/17"},
          {"POST", "/api/v1/imports"},
          {"PATCH", "/api/v1/points/17/position"},
          {"PUT", "/api/v1/points/17/position"},
          {"PATCH", "/api/v1/points/17"},
          {"PUT", "/api/v1/points/17"},
          {"DELETE", "/api/v1/points/17"},
          {"DELETE", "/api/v1/points/bulk_destroy"},
          {"POST", "/api/v1/points/reapply_anomaly_filter"}
        ] do
      assert {401, _, ""} = endpoint(c, method, path), path
    end

    assert {404, _, ""} = endpoint(c, "POST", "/api/v1/imports/pending")
    user!(%{api_key: @key, settings: %{"timezone" => "UTC"}})
    assert {200, _, "[]"} = endpoint(c, "GET", "/api/v1/imports", bearer())

    for {path, action} <- [
          {"/points", :points},
          {"/overland/batches", :overland},
          {"/owntracks/points", :owntracks},
          {"/traccar/points", :traccar}
        ] do
      assert route("POST", "/api/v1" <> path).plug_opts == {:native, action}
    end

    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_activate_i
  test "Merged storage proxy representations and guest upload refusals are terminal native responses",
       c do
    for path <-
          ~w(/rails/active_storage/blobs/proxy/invalid/photo.jpg /rails/active_storage/representations/proxy/invalid/invalid/photo.jpg /rails/active_storage/representations/redirect/invalid/invalid/photo.jpg /rails/active_storage/representations/invalid/invalid/photo.jpg) do
      assert {404, headers, _} = endpoint(c, "GET", path), path
      assert values(headers, "x-dawarich-handler") == ["phoenix-active-storage"]
    end

    assert {422, _, _} = endpoint(c, "POST", "/rails/active_storage/direct_uploads")
    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_06
  test "CORS preflight admits only pending import POST OPTIONS and exact production preview or test local origins",
       c do
    fixture = Jason.decode!(File.read!("test/fixtures/a12f2j/transport.json"))

    for row <- fixture["cors"] do
      headers = [
        {"Origin", row["origin"]},
        {"Access-Control-Request-Method", row["method"]},
        {"Access-Control-Request-Headers", "Content-Type, X-Upload"}
      ]

      {status, actual, ""} = endpoint(c, "OPTIONS", row["path"], headers)
      assert status == row["status"]

      assert Map.new(
               Enum.filter(actual, fn {name, _} ->
                 String.starts_with?(name, "access-control-") or name == "vary"
               end)
             ) == row["headers"]
    end

    refute DawarichWeb.Cors.allowed_origin?("http://localhost:8080", true)
    assert DawarichWeb.Cors.allowed_origin?("https://dawarich.app", true)
    assert DawarichWeb.Cors.allowed_origin?("https://preview-1.dawarich.pages.dev", true)
    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_07
  test "Pending upload success host limiter auth and errors retain source CORS headers without widening credentials",
       c do
    origin = [{"Origin", "https://dawarich.app"}]
    assert {404, headers, ""} = endpoint(c, "POST", "/api/v1/imports/pending", origin)
    assert values(headers, "access-control-allow-origin") == ["https://dawarich.app"]
    assert values(headers, "vary") == ["Origin"]
    assert values(headers, "access-control-allow-credentials") == []
    System.put_env("SELF_HOSTED", "false")
    assert {400, headers, _} = endpoint(c, "POST", "/api/v1/imports/pending", origin)
    assert values(headers, "access-control-allow-origin") == ["https://dawarich.app"]

    for denied <- [[], [{"Origin", "https://evil.test"}]] do
      assert {403, headers, ""} = endpoint(c, "POST", "/api/v1/imports/pending", denied)
      assert values(headers, "access-control-allow-origin") == []
      assert values(headers, "vary") == ["Origin"]
    end

    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_09
  test "Each API slice and Cable is native in explicit Cloud mode and HEAD matches that route source contract",
       c do
    for mode <- [nil, "true", "false"] do
      if mode, do: System.put_env("SELF_HOSTED", mode), else: System.delete_env("SELF_HOSTED")

      for path <-
            ~w(/api/v1/users/me /api/v1/notes /api/v1/visits /api/v1/places /api/v1/photos /api/v1/points /api/v1/stats /api/v1/plan /api/v1/imports /api/v1/families/locations) do
        assert {401, _, ""} = endpoint(c, "GET", path), "#{mode} #{path}"
        assert {401, _, ""} = endpoint(c, "HEAD", path), "#{mode} HEAD #{path}"
      end

      assert {404, _, "Page not found"} = endpoint(c, "GET", "/cable")

      assert {404, _, ""} =
               endpoint(c, "HEAD", "/cable", [{"Connection", "upgrade"}, {"Upgrade", "websocket"}])
    end

    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_02
  test "Native body parsing retains source duplicate nested encoding limits and accepted chunked multipart requests",
       c do
    fixture = Jason.decode!(File.read!("test/fixtures/a12f2j/transport.json"))

    for row <- fixture["params"], Map.has_key?(row, "params") do
      assert {401, _, ""} = endpoint(c, "GET", "/api/v1/photos?" <> row["query"])
    end

    for row <- fixture["params"], Map.has_key?(row, "params") do
      assert DawarichWeb.Api.SourceParams.decode(row["query"]) == {:ok, row["params"]}
    end

    for row <- fixture["params"], Map.has_key?(row, "error") do
      assert DawarichWeb.Api.SourceParams.decode(row["query"]) == {:error, 400}
    end

    conn = Plug.Test.conn(:post, "/api/v1/imports", ~s({"a":1,"a":2,"array":[null,1,null]}))

    conn =
      conn
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.assign(:api_tag, "api")

    parsed = DawarichWeb.Api.Body.call(conn, native: true)
    assert parsed.assigns.api_params == %{"a" => 2, "array" => [1]}

    multipart =
      "--j-boundary\r\nContent-Disposition: form-data; name=\"file\"; filename=\"trace.json\"\r\nContent-Type: application/json\r\n\r\n{}\r\n--j-boundary--\r\n"

    conn = Plug.Test.conn(:post, "/api/v1/imports", multipart)

    conn =
      conn
      |> Plug.Conn.put_req_header("content-type", "multipart/form-data; boundary=j-boundary")
      |> Plug.Conn.assign(:api_tag, "api")

    parsed = DawarichWeb.Api.Body.call(conn, native: true)
    assert %Plug.Upload{filename: "trace.json", path: file} = parsed.assigns.api_params["file"]
    assert File.read!(file) == "{}"

    chunked =
      Integer.to_string(byte_size(multipart), 16) <> "\r\n" <> multipart <> "\r\n0\r\n\r\n"

    assert {401, _, ""} =
             endpoint(
               c,
               "POST",
               "/api/v1/imports",
               [
                 {"Transfer-Encoding", "chunked"},
                 {"Content-Type", "multipart/form-data; boundary=j-boundary"}
               ],
               chunked
             )

    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_03
  test "Native requests retain source method override format suffix Accept XHR and routing precedence",
       c do
    user!(%{api_key: @key, settings: %{"timezone" => "UTC"}})

    headers =
      bearer() ++
        [
          {"Content-Type", "application/x-www-form-urlencoded"},
          {"X-HTTP-Method-Override", "DELETE"}
        ]

    assert {200, _, "[]"} =
             endpoint(c, "POST", "/api/v1/places?_method=DELETE", headers, "_method=GET")

    fixture = Jason.decode!(File.read!("test/fixtures/a12f2j/transport.json"))

    for row <- fixture["overrides"] do
      conn = Plug.Test.conn(row["method"], "/api/v1/places", row["body"])

      conn =
        conn
        |> Plug.Conn.put_req_header("content-type", row["content_type"])
        |> Plug.Conn.put_req_header("x-http-method-override", row["header"])

      assert DawarichWeb.Api.MethodOverride.call(conn, []).method == row["effective"]
    end

    for path <- ["/api/v1/places.json", "/api/v1/places.xml", "/api/v1/places.json?format=xml"] do
      assert {200, headers, "[]"} = endpoint(c, "GET", path, bearer())
      assert values(headers, "content-type") == ["application/json; charset=utf-8"]
    end

    conn =
      Plug.Test.conn(:get, "/api/v1/photos")
      |> Plug.Conn.put_req_header("accept", "application/xml;q=0.2, application/json;q=0.9")
      |> Plug.Conn.assign(:api_params, %{})

    assert DawarichWeb.Api.RequestFormat.decide(conn) == {:ok, :json, true}
    assert {401, _, ""} = endpoint(c, "HEAD", "/api/v1/photos.json")
    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_04
  test "API authentication retains key priority bearer cookies mobile markers Cloud payment and error header order",
       c do
    id = user!(%{api_key: @key, settings: %{"timezone" => "UTC"}})
    assert {401, _, ""} = endpoint(c, "GET", "/api/v1/notes?api_key=", bearer())

    assert {200, headers, "[]"} =
             endpoint(c, "GET", "/api/v1/notes", bearer() ++ [{"X-Dawarich-Client", "ios"}])

    [cookie] = values(headers, "set-cookie")
    value = cookie |> String.split(";") |> hd() |> String.split("=", parts: 2) |> List.last()

    assert {:ok, session} =
             Dawarich.RailsCookies.decrypt(
               value,
               "_dawarich_session",
               Dawarich.RailsSecret.fetch(),
               DateTime.utc_now()
             )

    assert session["dawarich_client"] == "ios"

    assert {401, _, ""} =
             endpoint(c, "GET", "/api/v1/notes", [{"Cookie", "_dawarich_session=" <> value}])

    System.put_env("SELF_HOSTED", "false")
    old_jwt = System.get_env("JWT_SECRET_KEY")
    System.put_env("JWT_SECRET_KEY", "synthetic-j-checkout-signing-key")

    on_exit(fn ->
      if old_jwt,
        do: System.put_env("JWT_SECRET_KEY", old_jwt),
        else: System.delete_env("JWT_SECRET_KEY")
    end)

    old_manager = System.get_env("MANAGER_URL")
    System.put_env("MANAGER_URL", "https://manager.example.test")

    on_exit(fn ->
      if old_manager,
        do: System.put_env("MANAGER_URL", old_manager),
        else: System.delete_env("MANAGER_URL")
    end)

    assert {200, _, "[]"} = endpoint(c, "GET", "/api/v1/places?tag_ids[]=untagged", bearer())
    Repo.query!("UPDATE users SET status=3 WHERE id=$1", [id])
    Dawarich.TtlCache.delete({DawarichWeb.RateLimit, @key})
    assert {402, headers, body} = endpoint(c, "GET", "/api/v1/notes", bearer())

    assert String.starts_with?(
             Jason.decode!(body)["resume_url"],
             "https://manager.example.test/auth/dawarich?token="
           )

    assert values(headers, "x-dawarich-response") == ["Hey, I'm alive and authenticated!"]
    no_upstream!(c.upstream)
  end

  @tag :a12f2_j_05
  test "Native unknown API paths bad parameters constraint misses and exceptions match source status body and HEAD",
       c do
    for {method, path} <- [
          {"GET", "/api/v1/unknown.json"},
          {"HEAD", "/api/v1/unknown.json"},
          {"GET", "/api/v1/digests/20.json"},
          {"PUT", "/api/v1/photos.json"},
          {"GET", "/api/v1/tiles/points/0/0/0"}
        ] do
      assert {404, _, body} = endpoint(c, method, path, [{"Accept", "application/json"}])
      assert body == if(method == "HEAD", do: "", else: ~s({"status":404,"error":"Not Found"}))
    end

    assert {400, _, body} =
             endpoint(c, "GET", "/api/v1/photos?a=%ZZ", [{"Accept", "application/json"}])

    assert Jason.decode!(body)["status"] == 400
    user!(%{api_key: @key, settings: %{"timezone" => "UTC"}})
    assert {404, _, _} = endpoint(c, "GET", "/api/v1/places/17suffix", bearer())
    no_upstream!(c.upstream)
  end

  defp bearer, do: [{"Authorization", "Bearer #{@key}"}, {"Accept", "application/json"}]

  defp route(method, path),
    do: Phoenix.Router.route_info(DawarichWeb.Router, method, path, "localhost")

  defp endpoint(c, method, path, headers \\ [], body \\ "") do
    upstream = Task.async(fn -> puma(c.upstream, "unexpected Rails replay") end)

    try do
      client = connect(c.port)

      length =
        if body != "" and
             not Enum.any?(headers, fn {name, _} ->
               String.downcase(name) == "transfer-encoding"
             end),
           do: "Content-Length: #{byte_size(body)}\r\n",
           else: ""

      send_raw(client, [
        "#{method} #{path} HTTP/1.1\r\nHost: localhost\r\n",
        length,
        Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
        "\r\n",
        body
      ])

      read_response(client, method: method)
    after
      Task.shutdown(upstream, :brutal_kill)
    end
  end
end
