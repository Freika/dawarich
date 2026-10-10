defmodule DawarichWeb.BrowserMapDataTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Repo
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    old = Map.take(System.get_env(), ~w(SELF_HOSTED DAWARICH_RAILS))
    System.put_env(%{"SELF_HOSTED" => "true", "DAWARICH_RAILS" => "off"})

    on_exit(fn ->
      for k <- ~w(SELF_HOSTED DAWARICH_RAILS),
          do: if(old[k], do: System.put_env(k, old[k]), else: System.delete_env(k))
    end)

    user =
      RailsUser.insert!(%{
        id: 96101,
        email: "cookie-map@dawarich.test",
        api_key: "synthetic-cookie-key",
        settings: %{"timezone" => "UTC"}
      })

    foreign = RailsUser.insert!(%{id: 96102, email: "foreign-map@dawarich.test"})
    point(user.id, 1_790_000_000)
    point(foreign.id, 1_790_000_000)
    %{id: user.id, foreign: foreign.id}
  end

  defp point(owner, at) do
    Repo.query!(
      "INSERT INTO points (user_id, timestamp, lonlat, created_at, updated_at) VALUES ($1, $2, ST_SetSRID(ST_MakePoint(13,52),4326),now(),now())",
      [owner, at]
    )
  end

  test "cookie flight snapshot is owned and constrained to the requested range", %{
    id: id,
    foreign: foreign
  } do
    for {owner, at} <- [
          {id, "2026-03-29 01:00:00"},
          {id, "2026-03-28 01:00:00"},
          {foreign, "2026-03-29 01:00:00"}
        ] do
      Repo.query!(
        "INSERT INTO flights (external_id, user_id, departure_time, arrival_time, from_lon, from_lat, to_lon, to_lat, created_at, updated_at) VALUES (extract(day from $2::text::timestamp)::integer, $1, $2::text::timestamp, $2::text::timestamp + interval '1 hour', 13, 52, 14, 53, now(), now())",
        [owner, at]
      )
    end

    conn = read(id, "/flights?start_at=2026-03-29T00:00:00Z&end_at=2026-03-29T03:00:00Z")
    assert conn.status == 200
    features = Jason.decode!(conn.resp_body)["features"]
    assert length(features) == 1

    [[owned]] =
      Repo.query!(
        "SELECT id FROM flights WHERE user_id = $1 AND departure_time::date = '2026-03-29'",
        [id]
      ).rows

    assert hd(features)["properties"]["id"] == owned
  end

  defp read(id, path), do: get(RailsUser.signed_in(id), "/native/map/data" <> path)

  test "cookie map read retains API entitlement and account isolation", %{id: id} do
    path = "/points?start_at=1780000000&end_at=1800000000&per_page=100"
    conn = read(id, path)
    assert conn.status == 200
    rows = Jason.decode!(conn.resp_body)
    assert length(rows) == 1
    [[owned]] = Repo.query!("SELECT id FROM points WHERE user_id = $1", [id]).rows
    assert hd(rows)["id"] == owned
    assert get_resp_header(conn, "vary") == ["Cookie"]
    assert get(build_conn(), "/native/map/data" <> path).status == 401

    assert get(
             build_conn() |> put_req_header("authorization", "Bearer synthetic-cookie-key"),
             "/native/map/data" <> path
           ).status == 401

    Repo.query!("UPDATE users SET status = 0 WHERE id = $1", [id])
    assert read(id, path).status == 200
    Repo.query!("UPDATE users SET status = 3 WHERE id = $1", [id])
    assert read(id, path).status == 402
    Repo.query!("UPDATE users SET status = 1, deleted_at = now() WHERE id = $1", [id])
    assert read(id, path).status == 401
  end

  test "browser route refuses writes", %{id: id} do
    for method <- [:post, :put, :patch, :delete] do
      conn =
        apply(Phoenix.ConnTest, :dispatch, [
          RailsUser.signed_in(id),
          @endpoint,
          method,
          "/native/map/data/points",
          %{}
        ])

      assert conn.status in [404, 405]
    end

    assert read(id, "/points?api_key=synthetic-cookie-key").status == 400
  end

  test "browser read is bounded and settings contain no provider credentials", %{id: id} do
    assert read(id, "/points?per_page=1001").status == 422
    assert read(id, "/points?per_page[]=1").status == 422

    Repo.query!("UPDATE users SET settings = settings || $1::jsonb WHERE id = $2", [
      %{"immich_api_key" => "synthetic-private-provider"},
      id
    ])

    conn = read(id, "/settings")
    assert conn.status == 200
    refute conn.resp_body =~ "synthetic-private-provider"
    refute conn.resp_body =~ "synthetic-cookie-key"
    assert Jason.decode!(conn.resp_body)["settings"]["timezone"] == "UTC"
  end

  test "cookie read cannot cross origin or accept a stale session", %{id: id} do
    conn =
      RailsUser.signed_in(id)
      |> put_req_header("sec-fetch-site", "cross-site")
      |> get("/native/map/data/points")

    assert conn.status == 403

    Repo.query!("UPDATE users SET encrypted_password = $1 WHERE id = $2", [
      String.duplicate("changed", 10),
      id
    ])

    assert read(id, "/points").status == 401
  end

  test "cookie tile reads preserve owned geometry validators and empty state", %{
    id: id,
    foreign: foreign
  } do
    path = "/tiles/points/0/0/0.mvt?start_at=1780000000&end_at=1800000000"
    conn = read(id, path)
    assert conn.status == 200
    assert byte_size(conn.resp_body) > 0
    assert get_resp_header(conn, "content-type") == ["application/vnd.mapbox-vector-tile"]
    assert get_resp_header(conn, "etag") != []
    point(foreign, 1_791_000_000)
    assert read(id, path).resp_body == conn.resp_body
    assert read(id, "/tiles/points/0/0/0.mvt?start_at=1800000001&end_at=1800000002").status == 204
  end
end
