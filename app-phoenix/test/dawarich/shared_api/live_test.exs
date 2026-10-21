defmodule Dawarich.SharedApi.LiveTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.SharedApi.Points

  @now ~U[2026-10-03 12:00:00Z]
  @id "a4951000-0000-4000-8000-000000000003"

  setup do
    owner = user!(%{settings: %{}})
    stamp = DateTime.to_naive(@now)

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(@id),
        name: "Synthetic live",
        user_id: owner,
        resource_type: 3,
        created_at: stamp,
        updated_at: stamp,
        settings: %{}
      }
    ])

    %{link: %{type: "live", user_id: owner, created_at: stamp, settings: %{}, resource_id: nil}}
  end

  test "live point is fresh at 900 seconds and empty at 901", %{link: link} do
    for age <- [899, 900, 901] do
      Repo.query!("DELETE FROM points")
      ts = DateTime.to_unix(@now) - age
      point!(link.user_id, ts)
      point!(link.user_id, ts + 1, true)
      point!(user!(), ts + 2)
      assert Points.live(link, @now) == {:ok, if(age <= 900, do: [[13.0, 52.0, ts]], else: [])}
    end
  end

  test "latest private point gives empty instead of an older public point", %{link: link} do
    point!(link.user_id, DateTime.to_unix(@now) - 10)
    point!(link.user_id, DateTime.to_unix(@now) - 1, false, [14.0, 53.0])
    private!(link.user_id)
    assert Points.live(link, @now) == {:ok, []}
    Repo.query!("UPDATE tags SET privacy_radius_meters = NULL")
    assert Points.live(link, @now) == {:ok, [[14.0, 53.0, DateTime.to_unix(@now) - 1]]}
  end

  test "live route honors Rails boolean cast and share-created cutoff", %{link: link} do
    ts = DateTime.to_unix(@now)
    for offset <- [-1, 0, 1], do: point!(link.user_id, ts + offset)
    point!(link.user_id, ts + 2, true)
    point!(user!(), ts + 3)
    point!(link.user_id, ts + 4, false, [14.0, 53.0])
    private!(link.user_id)

    for flag <- [nil, false, "", "0", "false", "FALSE", "f", "F", "off", "OFF"] do
      assert Points.route(%{link | settings: %{"show_route" => flag}}) == {:ok, []}
    end

    for flag <- [true, "true", "yes", "1", 0, "anything"] do
      assert Points.route(%{link | settings: %{"show_route" => flag}}) ==
               {:ok, [[13.0, 52.0, ts], [13.0, 52.0, ts + 1]]}
    end
  end

  test "nonlive route is empty and live current position is not public cached", ctx do
    link = ctx.link
    ts = DateTime.utc_now() |> DateTime.to_unix()
    point!(link.user_id, ts)

    Repo.query!(
      "INSERT INTO tracks (id,user_id,start_at,end_at,original_path,created_at,updated_at) VALUES (951201,$1,NOW(),NOW(),ST_GeomFromText('LINESTRING(13 52,14 53)',4326),NOW(),NOW())",
      [link.user_id]
    )

    Repo.query!("UPDATE points SET track_id = 951201")
    assert Points.route(%{link | type: "track", resource_id: 951_201}) == {:ok, []}

    assert {200, headers, body} =
             ctx.port
             |> request("/api/v1/shared/#{@id}/points", [{"Accept", "application/json"}])
             |> read_response()

    assert Jason.decode!(body) == [[13.0, 52.0, ts]]
    assert {"cache-control", "max-age=0, private, must-revalidate"} in headers
    no_upstream!(ctx.upstream)
  end

  defp point!(user, ts, anomaly \\ false, [lon, lat] \\ [13.0, 52.0]) do
    Repo.query!(
      "INSERT INTO points (user_id,timestamp,anomaly,lonlat,created_at,updated_at) VALUES ($1,$2,$3,ST_SetSRID(ST_MakePoint($4,$5),4326)::geography,NOW(),NOW())",
      [user, ts, anomaly, lon, lat]
    )
  end

  defp private!(user) do
    Repo.query!(
      "INSERT INTO places (id,user_id,name,latitude,longitude,lonlat,created_at,updated_at) VALUES (951501,$1,'Synthetic private',53,14,ST_SetSRID(ST_MakePoint(13,52),4326)::geography,NOW(),NOW())",
      [user]
    )

    Repo.query!(
      "INSERT INTO tags (id,user_id,name,privacy_radius_meters,created_at,updated_at) VALUES (951601,$1,'Synthetic privacy',100,NOW(),NOW())",
      [user]
    )

    Repo.query!(
      "INSERT INTO taggings (tag_id,taggable_type,taggable_id,created_at,updated_at) VALUES (951601,'Place',951501,NOW(),NOW())"
    )
  end
end
