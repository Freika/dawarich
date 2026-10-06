defmodule DawarichWeb.A12f2CClosureTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.Redis

  setup do
    Dawarich.ApiEndpointCase.clear_transport_env()
    start_supervised!(hd(Redis.child_specs()))
    start_supervised!(hd(Redis.cache_child_specs()))

    user = %{
      id: user!(%{plan: 1, settings: %{}}),
      timezone: "Etc/UTC",
      plan: 1,
      active_until: nil
    }

    {:ok, user: user}
  end

  @tag :a12f2_c_03
  test "Point tiles retain binary MVT geometry properties zoom bounds epoch ETag and failure framing",
       %{user: user} do
    point(user.id, 1_735_689_600, false)
    point(user.id, 1_735_689_601, true)
    point(user!(%{}), 1_735_689_602, false)

    params = %{
      "z" => "10",
      "x" => "548",
      "y" => "338",
      "start_at" => "1735689600",
      "end_at" => "1735690000"
    }

    assert {:ok, tile, features} = invoke(Dawarich.Tiles.Points, :fetch, [user, params])
    assert is_binary(tile) and byte_size(tile) > 0
    assert {:ok, ^tile, _} = Dawarich.Tiles.Points.fetch(user, Map.put(params, "y", "338.mvt"))
    assert [%{"count" => 1, "timestamp" => 1_735_689_600, "revision" => 0}] = features
    assert tile =~ "points"
    conn = tile_conn(user, params)

    assert %{status: 200, resp_body: ^tile} =
             first = invoke(DawarichWeb.Api.PointTilesController, :call, [conn, :show])

    assert Plug.Conn.get_resp_header(first, "content-type") == [
             "application/vnd.mapbox-vector-tile"
           ]

    assert Plug.Conn.get_resp_header(first, "cache-control") == ["max-age=300, private"]
    [etag] = Plug.Conn.get_resp_header(first, "etag")

    assert %{status: 304, resp_body: ""} =
             invoke(DawarichWeb.Api.PointTilesController, :call, [
               Plug.Conn.put_req_header(conn, "if-none-match", etag),
               :show
             ])

    Redis.cache_command(["SET", "points:tile_epoch:#{user.id}:2025", "synthetic-new-epoch"])
    changed = invoke(DawarichWeb.Api.PointTilesController, :call, [conn, :show])
    refute Plug.Conn.get_resp_header(changed, "etag") == [etag]

    for bad <- [
          %{"x" => "1024"},
          %{"z" => "23"},
          %{"x" => "bad"},
          %{"end_at" => ""},
          %{"start_at" => "bad"},
          %{"start_at" => "1735690001"}
        ] do
      failed =
        invoke(DawarichWeb.Api.PointTilesController, :call, [
          tile_conn(user, Map.merge(params, bad)),
          :show
        ])

      assert failed.status == 400
      assert Plug.Conn.get_resp_header(failed, "cache-control") == ["no-store"]
      assert Plug.Conn.get_resp_header(failed, "etag") == []
    end

    assert {:ok, "", []} =
             invoke(Dawarich.Tiles.Points, :fetch, [user, Map.put(params, "import_id", "999999")])

    low = Map.merge(params, %{"z" => "0", "x" => "0", "y" => "0"})
    assert {:ok, _, [feature]} = invoke(Dawarich.Tiles.Points, :fetch, [user, low])
    refute Map.has_key?(feature, "id")
    fixture = oracle("points_base")
    seed(fixture["setup"])
    source_user = %{user | id: 810_001, timezone: "Etc/UTC"}
    assert {:ok, bytes, _} = Dawarich.Tiles.Points.fetch(source_user, params)
    assert bytes == Base.decode64!(fixture["body_base64"])
    epoch_seed(source_user.id)
    response = DawarichWeb.Api.PointTilesController.call(tile_conn(source_user, params), :show)
    assert Plug.Conn.get_resp_header(response, "etag") == [fixture["headers"]["etag"]]
  end

  @tag :a12f2_c_04
  test "Track tiles retain segment speed properties geometry clipping plan scope and conditional bytes",
       %{user: user} do
    track = track(user.id)

    for {offset, lng} <- [{0, 13.1}, {60, 13.001}, {120, 13.002}, {180, 13.003}, {300, 13.004}] do
      point(user.id, 1_735_689_600 + offset, false, track, lng)
    end

    params = %{
      "z" => "10",
      "x" => "548",
      "y" => "338",
      "start_at" => "1735689660",
      "end_at" => "1735689780",
      "speed_coloring" => "true"
    }

    assert {:ok, tile, features} = invoke(Dawarich.Tiles.Tracks, :fetch, [user, params])
    assert tile =~ "tracks"
    assert features != []
    assert Enum.all?(features, &(&1["segment_speed"] < 10))

    assert Enum.all?(
             features,
             &(&1["start_timestamp"] == 1_735_689_660 and &1["end_timestamp"] == 1_735_689_780)
           )

    assert Enum.all?(features, &(&1["dominant_mode"] == "driving" and &1["color"] == "#6366F1"))
    conn = tile_conn(user, params)

    assert %{status: 200, resp_body: ^tile} =
             first = invoke(DawarichWeb.Api.TrackTilesController, :call, [conn, :show])

    [etag] = Plug.Conn.get_resp_header(first, "etag")

    assert %{status: 304} =
             invoke(DawarichWeb.Api.TrackTilesController, :call, [
               Plug.Conn.put_req_header(conn, "if-none-match", etag),
               :show
             ])

    assert {:ok, "", []} =
             Dawarich.Tiles.Tracks.fetch(user, Map.put(params, "import_id", "999999"))

    fixture = oracle("tracks_base")
    seed(fixture["setup"])
    source_user = %{user | id: 810_001}

    source_params =
      Map.merge(params, %{
        "start_at" => "1735689600",
        "end_at" => "1735690000",
        "speed_coloring" => "false"
      })

    assert {:ok, bytes, _} = Dawarich.Tiles.Tracks.fetch(source_user, source_params)
    assert bytes == Base.decode64!(fixture["body_base64"])

    assert {:ok, bytes, _} =
             Dawarich.Tiles.Tracks.fetch(
               source_user,
               Map.put(source_params, "speed_coloring", "true")
             )

    assert bytes == Base.decode64!(oracle("tracks_speed")["body_base64"])
    epoch_seed(source_user.id)

    response =
      DawarichWeb.Api.TrackTilesController.call(tile_conn(source_user, source_params), :show)

    assert Plug.Conn.get_resp_header(response, "etag") == [fixture["headers"]["etag"]]
  end

  @tag :a12f2_c_05
  test "Timeline and privacy zones preserve ownership zoned ranges interleaving limits and serialized geometry",
       %{user: user} do
    track = track(user.id)

    Repo.query!(
      "INSERT INTO visits (user_id, name, status, started_at, ended_at, duration, created_at, updated_at) VALUES ($1,'synthetic',1,'2025-01-01','2025-01-01 00:05:00',5,NOW(),NOW())",
      [user.id]
    )

    track(user!(%{}))
    params = %{"start_at" => "2025-01-01T00:00:00Z", "end_at" => "2025-01-01T23:59:59Z"}
    assert {:ok, %{days: [day]}} = invoke(Dawarich.Timeline.Api, :fetch, [user, params])
    assert [%{type: "visit"}, %{type: "journey", track_id: ^track}] = day.entries
    assert day.summary.time_stationary_minutes == 5
    assert day.summary.time_moving_minutes == 5
    refute Map.has_key?(hd(day.entries), :start_s)

    assert {:error, 400, "start_at and end_at are required"} =
             Dawarich.Timeline.Api.fetch(user, %{})

    assert {:error, 400, "Date range cannot exceed 31 days"} =
             Dawarich.Timeline.Api.fetch(user, Map.put(params, "end_at", "2025-03-01"))

    assert {:ok, %{days: []}} =
             Dawarich.Timeline.Api.fetch(user, Map.put(params, "start_at", "2025-01-02"))

    zoned = %{user | timezone: "Europe/Berlin"}

    assert {:ok, %{days: [%{date: "2025-01-01", entries: [visit | _]}]}} =
             Dawarich.Timeline.Api.fetch(zoned, params)

    assert visit.started_at == "2025-01-01T01:00:00+01:00"

    [[tag]] =
      Repo.query!(
        "INSERT INTO tags (user_id,name,privacy_radius_meters,created_at,updated_at) VALUES ($1,'synthetic',100,NOW(),NOW()) RETURNING id",
        [user.id]
      ).rows

    Repo.query!(
      "INSERT INTO tags (user_id,name,privacy_radius_meters,created_at,updated_at) VALUES ($1,'other',200,NOW(),NOW())",
      [user!(%{})]
    )

    assert [%{tag_id: ^tag, tag_name: "synthetic", radius_meters: 100, places: []}] =
             invoke(Dawarich.MapApi.PrivacyZones, :fetch, [user])
  end

  @tag :a12f2_c_06
  test "Hexagon index and bounds retain H3 resolution Pro entitlement shared grants and source geometry",
       %{user: user} do
    fixture = oracle("hexagons")
    seed(fixture["setup"])
    owner = %{user | id: 810_001}
    params = %{"start_date" => "2025-01-01", "end_date" => "2025-01-02"}
    assert {:ok, result} = invoke(Dawarich.MapApi.Hexagons, :fetch, [owner, params])
    expected = Jason.decode!(fixture["body"])
    assert result["metadata"] == expected["metadata"]
    assert length(result["features"]) == 1
    coords = hd(result["features"])["geometry"]["coordinates"] |> hd()
    want = hd(expected["features"])["geometry"]["coordinates"] |> hd()
    assert length(coords) == length(want)

    for {[lng, lat], [wlng, wlat]} <- Enum.zip(coords, want) do
      assert_in_delta lng, wlng, 1.0e-10
      assert_in_delta lat, wlat, 1.0e-10
    end

    assert {:ok, bounds} = invoke(Dawarich.MapApi.Hexagons, :bounds, [owner, params])
    assert bounds == Jason.decode!(oracle("bounds")["body"])
    assert {:ok, %{"features" => []}} = Dawarich.MapApi.Hexagons.fetch(user, params)
    uuid = "00000000-0000-0000-0000-000000000001"

    Repo.query!(
      "UPDATE stats SET sharing_uuid=$1::text::uuid,sharing_settings='{\"enabled\":true}' WHERE id=780001",
      [uuid]
    )

    assert {:ok, shared} = Dawarich.MapApi.Hexagons.fetch(user, Map.put(params, "uuid", uuid))
    assert shared == result
    Repo.query!("UPDATE users SET deleted_at=NOW() WHERE id=$1", [owner.id])
    assert {:error, 404, _} = Dawarich.MapApi.Hexagons.fetch(user, Map.put(params, "uuid", uuid))
    Repo.query!("UPDATE users SET deleted_at=NULL WHERE id=$1", [owner.id])
    Repo.query!("UPDATE stats SET sharing_settings='{\"enabled\":false}' WHERE id=780001")
    assert {:error, 404, _} = Dawarich.MapApi.Hexagons.fetch(user, Map.put(params, "uuid", uuid))
    assert {:error, 400, _} = Dawarich.MapApi.Hexagons.bounds(owner, %{})
  end

  @tag :a12f2_c_07
  test "Fog retains strict dates viewport H3 exclusions privacy and source service failures", %{
    user: user
  } do
    fixture = oracle("fog")
    seed(fixture["setup"])
    owner = %{user | id: 810_001}
    params = %{"start_date" => "2025-01-01", "end_date" => "2025-01-02"}
    assert {:ok, result} = invoke(Dawarich.MapApi.Fog, :fetch, [owner, params])
    assert result == Jason.decode!(fixture["body"])

    Repo.query!("UPDATE stats SET h3_hex_ids=$1::text::jsonb WHERE id=780001", [
      Jason.encode!([
        ["pre-range", 1, 1_735_603_200, 1_735_603_300],
        ["in-range", 2, 1_735_689_600, 1_735_689_900],
        ["in-range", 1, nil, nil],
        ["after-range", 1, 1_735_862_400, 1_735_862_500],
        nil,
        [nil, 0, nil, nil]
      ])
    ])

    assert {:ok, %{"h3_indexes" => ["in-range"], "metadata" => %{"count" => 1}}} =
             Dawarich.MapApi.Fog.fetch(owner, params)

    assert {:ok, %{"h3_indexes" => []}} = Dawarich.MapApi.Fog.fetch(user, params)

    assert {:error, 400, "Invalid date format"} =
             Dawarich.MapApi.Fog.fetch(owner, Map.put(params, "start_date", "bad"))

    assert {:error, 400, _} = Dawarich.MapApi.Fog.fetch(owner, %{})

    assert {:ok, %{"h3_indexes" => []}} =
             Dawarich.MapApi.Fog.fetch(owner, Map.put(params, "start_date", "2026-01-01"))
  end

  @tag :a12f2_c_02
  test "Spatial metadata preserves GeoJSON history scope epochs zoned months and conditional responses",
       %{user: user} do
    fixture = oracle("visited")
    seed(fixture["setup"])
    owner = %{user | id: 810_001, timezone: "Europe/Berlin"}
    params = %{"start_at" => "1735689600", "end_at" => "1735690000"}
    assert {:ok, result, etag} = invoke(Dawarich.MapApi.Countries, :visited, [owner, params])
    assert result == Jason.decode!(fixture["body"])
    assert {:ok, %{"countries" => []}, _} = Dawarich.MapApi.Countries.visited(user, params)
    assert {:ok, _, ^etag} = Dawarich.MapApi.Countries.visited(owner, params)

    Redis.cache_command([
      "SET",
      "points:tile_epoch:#{owner.id}:2025",
      :crypto.strong_rand_bytes(8) |> Base.encode16()
    ])

    assert {:ok, _, changed} = Dawarich.MapApi.Countries.visited(owner, params)
    refute changed == etag

    for bad <- [%{}, Map.put(params, "start_at", "bad"), Map.put(params, "end_at", "1735689599")] do
      assert {:error, 422, "start_at and end_at must be valid timestamps"} =
               Dawarich.MapApi.Countries.visited(owner, bad)
    end

    assert {:ok, bytes} = invoke(Dawarich.MapApi.Countries, :borders, [])

    assert :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) ==
             oracle("borders")["sha256"]

    Redis.cache_command(["UNLINK", "dawarich/user_#{owner.id}_years_tracked"])
    assert result = invoke(Dawarich.MapApi.TrackedMonths, :fetch, [owner])
    assert result == Jason.decode!(oracle("tracked_months_berlin")["body"])
    assert %{"year" => 2024, "months" => ["Dec"]} in result
    assert {:ok, cache} = Redis.cache_command(["GET", "dawarich/user_#{owner.id}_years_tracked"])

    assert {:ok, %{value: [%{{:ruby_symbol, "year"} => 2025} | _]}} =
             Dawarich.RailsCache.Wire.decode(cache)

    assert {:ok, ttl} = Redis.cache_command(["TTL", "dawarich/user_#{owner.id}_years_tracked"])
    assert ttl in 86390..86400
    assert result == Dawarich.MapApi.TrackedMonths.fetch(owner)

    package =
      Path.join(
        System.tmp_dir!(),
        "country-package-#{System.unique_integer([:positive])}/dawarich-0.1.0"
      )

    File.mkdir_p!(Path.join(package, "ebin"))
    File.mkdir_p!(Path.join(package, "priv"))
    packaged = ~s({"synthetic":"packaged"})

    codes = %{
      "borders_gzip_base64" => packaged |> :zlib.gzip() |> Base.encode64(),
      "visited_aliases" => %{}
    }

    File.write!(Path.join(package, "priv/country_codes.json"), Jason.encode!(codes))
    original = Application.app_dir(:dawarich, "ebin") |> String.to_charlist()

    try do
      assert :code.replace_path(:dawarich, String.to_charlist(Path.join(package, "ebin"))) == true
      assert Dawarich.MapApi.Countries.borders() == {:ok, packaged}
    after
      :code.replace_path(:dawarich, original)
      File.rm_rf!(Path.dirname(package))
    end
  end

  @tag :a12f2_c_06_robust
  test "Robust history bounds retain supported cells and total source point counts", %{user: user} do
    for i <- 0..49, do: point(user.id, 1_735_689_600 + i, false, nil, 13.0)
    point(user.id, 1_735_689_700, false, nil, 100.0)
    params = %{"start_date" => "2025-01-01", "end_date" => "2025-01-02", "robust" => "true"}
    assert {:ok, bounds} = Dawarich.MapApi.Hexagons.bounds(user, params)
    assert bounds["point_count"] == 51
    assert bounds["max_lng"] == 13.0
    assert {:ok, exact} = Dawarich.MapApi.Hexagons.bounds(user, Map.delete(params, "robust"))
    assert exact["max_lng"] == 100.0
  end

  @tag :a12f2_c_08
  test "Digest reads preserve malformed stored JSONB year constraints distance units and source failures",
       %{user: user} do
    Repo.query!(
      "INSERT INTO digests (user_id,year,period_type,distance,toponyms,created_at,updated_at) VALUES ($1,2024,1,12345,'[]', '2025-01-01','2025-01-01')",
      [user.id]
    )

    assert {:ok, term, opts} =
             invoke(Dawarich.Digests.ReadClosure, :show, [user, "2024junk", %{}, []])

    body =
      term
      |> Dawarich.ReleaseMigrations.Effects.Support.Ruby.json()
      |> IO.iodata_to_binary()
      |> Jason.decode!()

    assert body["year"] == 2024
    assert body["distance"]["converted"] == 12
    assert opts[:cache_control] == "max-age=3600, private"
    assert :not_found == invoke(Dawarich.Digests.ReadClosure, :show, [user, "1970", %{}, []])

    assert {:not_modified, _} =
             invoke(Dawarich.Digests.ReadClosure, :show, [
               user,
               "2024",
               %{},
               [{"if-modified-since", "Wed, 01 Jan 2025 00:00:00 GMT"}]
             ])

    Repo.query!("UPDATE digests SET toponyms = '{\"country\":\"Germany\"}' WHERE user_id=$1", [
      user.id
    ])

    assert {:error, 500} == invoke(Dawarich.Digests.ReadClosure, :show, [user, "2024", %{}, []])

    assert {:ok, _, []} =
             invoke(Dawarich.Digests.ReadClosure, :index, [user, ~U[2025-06-01 00:00:00Z]])

    response =
      DawarichWeb.Api.DigestsController.call(
        tile_conn(user, %{}) |> Map.put(:path_params, %{"year" => "2024"}),
        :closure_show
      )

    assert response.status == 500
    refute Map.has_key?(response.private, :rails_replay)
    source = oracle("digest_valid")
    seed(source["setup"])

    assert {:ok, valid, _} =
             Dawarich.Digests.ReadClosure.show(%{user | id: 810_001}, "2024junk", %{}, [])

    assert valid
           |> Dawarich.ReleaseMigrations.Effects.Support.Ruby.json()
           |> IO.iodata_to_binary()
           |> Jason.decode!() == Jason.decode!(source["body"])

    source = oracle("digest_malformed")
    Repo.query!("DELETE FROM digests WHERE id=770001")
    Dawarich.Test.ApiGolden.insert!("digests", source["setup"]["digests"])
    assert source["status"] == 500

    assert {:error, 500} =
             Dawarich.Digests.ReadClosure.show(%{user | id: 810_001}, "2024junk", %{}, [])
  end

  @tag :a12f2_c_09
  test "MCP GET POST DELETE retain stateless JSON RPC negotiation protocol headers and Bearer only auth",
       %{user: user} do
    Repo.query!("UPDATE users SET api_key='synthetic-mcp' WHERE id=$1", [user.id])

    headers = [
      {"authorization", "Bearer synthetic-mcp"},
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    assert {:ok, actor} = invoke(Dawarich.Mcp.Transport, :authorize, [headers, %{}])
    assert actor.id == user.id

    assert {:error, 401} =
             invoke(Dawarich.Mcp.Transport, :authorize, [
               Enum.reject(headers, &(elem(&1, 0) == "authorization")),
               %{"api_key" => "synthetic-mcp"}
             ])

    init =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => "client-1",
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2025-11-25",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "synthetic", "version" => "1"}
        }
      })

    assert {200, reply} = invoke(Dawarich.Mcp.Transport, :request, ["POST", headers, init, actor])
    assert reply["id"] == "client-1"
    assert reply["result"]["serverInfo"]["name"] == "dawarich"
    assert reply["result"]["protocolVersion"] == "2025-11-25"
    assert reply["result"] == Jason.decode!(oracle("mcp_initialize")["body"])["result"]
    assert {405, _} = Dawarich.Mcp.Transport.request("GET", headers, "", actor)

    assert {200, %{"success" => true}} =
             Dawarich.Mcp.Transport.request("DELETE", headers, "", actor)

    assert {202, nil} =
             Dawarich.Mcp.Transport.request(
               "POST",
               headers,
               ~s({"jsonrpc":"2.0","method":"notifications/initialized"}),
               actor
             )

    assert {400, %{"error" => %{"code" => -32600}}} =
             Dawarich.Mcp.Transport.request("POST", headers, "[]", actor)

    assert {400, %{"error" => %{"code" => -32700}}} =
             Dawarich.Mcp.Transport.request("POST", headers, "{", actor)

    assert {406, _} =
             Dawarich.Mcp.Transport.request(
               "POST",
               List.keydelete(headers, "accept", 0),
               init,
               actor
             )

    assert {400, _} =
             Dawarich.Mcp.Transport.request(
               "DELETE",
               [{"mcp-protocol-version", "invalid"} | headers],
               "",
               actor
             )
  end

  @tag :a12f2_c_10
  test "MCP tools preserve schemas actor scoped results pagination privacy and JSON RPC errors",
       %{user: user} do
    expected = point(user.id, 1_735_689_600, false)
    point(user.id, 1_735_689_601, true)
    point(user!(%{}), 1_735_689_602, false)

    assert {:ok, result} =
             invoke(Dawarich.Mcp.Tools, :call, [
               user,
               %{"name" => "get_latest_location", "arguments" => %{}}
             ])

    assert result["structuredContent"]["point"]["id"] == expected
    assert result["isError"] == false

    assert {:ok, %{"isError" => true}} =
             Dawarich.Mcp.Tools.call(user, %{
               "name" => "get_latest_location",
               "arguments" => %{"timezone" => "UTC"}
             })

    assert {:rpc_error, -32602, _} =
             Dawarich.Mcp.Tools.call(user, %{"name" => "unknown", "arguments" => %{}})

    fixture = oracle("timeline")
    seed(fixture["setup"])
    owner = %{user | id: 810_001}

    assert {:ok, latest} =
             Dawarich.Mcp.Tools.call(owner, %{"name" => "get_latest_location", "arguments" => %{}})

    assert latest == Jason.decode!(oracle("mcp_latest")["body"])["result"]

    assert {:ok, timeline} =
             Dawarich.Mcp.Tools.call(owner, %{
               "name" => "get_timeline",
               "arguments" => %{"start_at" => "2025-01-01", "end_at" => "2025-01-01"}
             })

    assert timeline == Jason.decode!(oracle("mcp_timeline")["body"])["result"]

    assert {:ok, search} =
             Dawarich.Mcp.Tools.call(owner, %{
               "name" => "search_visits",
               "arguments" => %{"query" => "synthetic", "limit" => 1}
             })

    assert search == Jason.decode!(oracle("mcp_search")["body"])["result"]

    assert {:ok, %{"isError" => true}} =
             Dawarich.Mcp.Tools.call(owner, %{
               "name" => "get_timeline",
               "arguments" => %{"start_at" => "2025-01-01", "end_at" => "2025-01-08"}
             })

    assert {:ok, none} =
             Dawarich.Mcp.Tools.call(owner, %{
               "name" => "search_visits",
               "arguments" => %{"query" => "%%"}
             })

    assert none["structuredContent"]["total_count"] == 0

    assert Dawarich.Mcp.Tools.list() ==
             Jason.decode!(oracle("mcp_tools")["body"])["result"]["tools"]
  end

  defp track(user_id) do
    [[id]] =
      Repo.query!(
        "INSERT INTO tracks (user_id, start_at, end_at, original_path, distance, avg_speed, duration, dominant_mode, created_at, updated_at) VALUES ($1, '2025-01-01', '2025-01-01 00:05:00', 'SRID=4326;LINESTRING(13 52,13.004 52)', 300, 4, 300, 5, NOW(), NOW()) RETURNING id",
        [user_id]
      ).rows

    id
  end

  defp invoke(module, fun, args) do
    assert Code.ensure_loaded?(module) and function_exported?(module, fun, length(args)),
           "missing native #{inspect(module)}.#{fun}"

    apply(module, fun, args)
  end

  defp epoch_seed(id) do
    for layer <- ~w(points tracks), year <- [2025, "all"] do
      Redis.cache_command([
        "SET",
        "#{layer}:tile_epoch:#{id}:#{year}",
        "synthetic-#{layer}-#{year}"
      ])
    end
  end

  defp oracle(name),
    do: "test/fixtures/a12f2c/closure.json" |> File.read!() |> Jason.decode!() |> Map.fetch!(name)

  defp seed(setup) do
    for table <-
          ~w(users countries point_sources tracks track_segments points visits stats digests) do
      if setup[table], do: Dawarich.Test.ApiGolden.insert!(table, setup[table])
    end
  end

  defp point(user_id, timestamp, anomaly, track_id \\ nil, longitude \\ 13.0) do
    [[id]] =
      Repo.query!(
        "INSERT INTO points (user_id, timestamp, lonlat, anomaly, track_id, created_at, updated_at) VALUES ($1, $2, ST_SetSRID(ST_MakePoint($3,52),4326), $4, $5, NOW(), NOW()) RETURNING id",
        [user_id, timestamp, longitude, anomaly, track_id]
      ).rows

    id
  end

  defp tile_conn(user, params) do
    Plug.Test.conn(:get, "/synthetic.mvt")
    |> Plug.Conn.assign(:api_user, user)
    |> Plug.Conn.assign(:api_params, params)
    |> Plug.Conn.assign(:api_started, System.monotonic_time())
    |> Plug.Conn.assign(:api_headers, [])
    |> Plug.Conn.assign(:api_request_id, "synthetic")
    |> Plug.Conn.assign(:api_tag, "closure")
    |> Plug.Conn.assign(:api_vary, false)
    |> Plug.Conn.assign(:api_if_none_match, nil)
  end
end
