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

  defp oracle(name),
    do: "test/fixtures/a12f2c/closure.json" |> File.read!() |> Jason.decode!() |> Map.fetch!(name)

  defp seed(setup) do
    for table <- ~w(users countries point_sources tracks track_segments points) do
      Dawarich.Test.ApiGolden.insert!(table, setup[table])
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
  end
end
