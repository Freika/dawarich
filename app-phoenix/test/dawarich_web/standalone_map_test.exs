defmodule DawarichWeb.StandaloneMapTest do
  use Dawarich.DataCase, async: false
  import Plug.Conn

  setup do
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true"})
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    key = "standalone-map-#{System.unique_integer([:positive])}"
    id = user!(%{api_key: key, settings: %{"timezone" => "UTC"}})

    on_exit(fn ->
      for name <- ~w(DAWARICH_RAILS SELF_HOSTED) do
        if env[name], do: System.put_env(name, env[name]), else: System.delete_env(name)
      end
    end)

    %{id: id, key: key}
  end

  test "standalone map settings use native API authentication and preserve coexistence", %{
    key: key
  } do
    conn = request("/api/v1/settings", key)
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["settings"]["timezone"] == "UTC"
    assert request("/api/v1/settings", "absent").status == 401
    System.delete_env("DAWARICH_RAILS")
    conn = Plug.Test.conn(:get, "/api/v1/settings")
    route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", conn.path_info, conn.host)
    refute DawarichWeb.Strangler.gate_open?(route, conn)
  end

  test "standalone point tiles contain only the authenticated account and requested range", %{
    id: id,
    key: key
  } do
    point(id, 1_750_000_000)
    path = "/api/v1/tiles/points/0/0/0.mvt?start_at=1700000000&end_at=1800000000"
    conn = request(path, key)
    assert conn.status == 200
    assert byte_size(conn.resp_body) > 0
    assert get_resp_header(conn, "content-type") == ["application/vnd.mapbox-vector-tile"]
    point(user!(), 1_750_000_000)
    point(id, 1_650_000_000)
    assert request(path, key).resp_body == conn.resp_body
    assert request(String.replace(path, "/0/0/0.mvt", "/0/2/0.mvt"), key).status == 400
  end

  test "standalone track tiles are scoped and advanced coloring terminates natively", %{
    id: id,
    key: key
  } do
    track(id)
    path = "/api/v1/tiles/tracks/0/0/0.mvt?start_at=1700000000&end_at=1800000000"
    conn = request(path, key)
    assert conn.status == 200
    assert byte_size(conn.resp_body) > 0
    track(user!())
    assert request(path, key).resp_body == conn.resp_body
    colored = request(path <> "&speed_coloring=true", key)
    assert colored.status == 200
    assert colored.resp_body == conn.resp_body
  end

  test "standalone map bounds and progress read native state without account leakage", %{
    id: id,
    key: key
  } do
    point(id, 1_750_000_000)
    point(user!(), 1_750_000_000)
    conn = request("/api/v1/maps/hexagons/bounds?start_date=1700000000&end_date=1800000000", key)
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["point_count"] == 1
    assert Jason.decode!(conn.resp_body)["min_lng"] == 0.0
    assert request("/api/v1/settings/transportation_recalculation_status", key).status == 200
  end

  test "standalone recalculation progress rejects inactive accounts without restricting settings",
       %{id: id, key: key} do
    assert request("/api/v1/settings/transportation_recalculation_status", key).status == 200
    Repo.query!("UPDATE users SET status=0 WHERE id=$1", [id])
    assert request("/api/v1/settings/transportation_recalculation_status", key).status == 401
    assert request("/api/v1/settings", key).status == 200

    Repo.query!("UPDATE users SET status=1, active_until=NOW()-interval '1 day' WHERE id=$1", [id])

    assert request("/api/v1/settings/transportation_recalculation_status", key).status == 401
  end

  test "standalone map preserves stored invalid timezone with source admission fallback", %{
    id: id,
    key: key
  } do
    Repo.query!("UPDATE users SET settings = $2 WHERE id = $1", [
      id,
      %{"timezone" => "unsupported"}
    ])

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        conn = request("/api/v1/settings", key)
        assert conn.status == 200
        assert Jason.decode!(conn.resp_body)["settings"]["timezone"] == "unsupported"
      end)

    refute log =~ "standalone_map_timezone"
  end

  defp request(path, key) do
    Plug.Test.conn(:get, path)
    |> put_req_header("authorization", "Bearer " <> key)
    |> DawarichWeb.Endpoint.call([])
  end

  defp point(id, stamp) do
    Repo.query!(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) VALUES ($1, $2, ST_SetSRID(ST_MakePoint(0,0),4326), NOW(), NOW())",
      [id, stamp]
    )
  end

  defp track(id) do
    Repo.query!(
      "INSERT INTO tracks (user_id, start_at, end_at, original_path, distance, created_at, updated_at) VALUES ($1, '2025-06-01', '2025-06-02', ST_GeomFromText('LINESTRING(-10 0,10 0)',4326), 1000, NOW(), NOW())",
      [id]
    )
  end
end
