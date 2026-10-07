defmodule Dawarich.AreasTest do
  use Dawarich.JobsCase, async: true, group: :scratch_db

  alias Dawarich.Areas

  setup do
    [[user_id]] =
      rows(
        "INSERT INTO users (email, created_at, updated_at) VALUES ('areas@example.test', now(), now()) RETURNING id"
      )

    %{user_id: user_id}
  end

  defp area!(user_id, attrs \\ %{}) do
    %{name: name, latitude: lat, longitude: lon, radius: radius} =
      Map.merge(%{name: "Leipzig", latitude: 51.339695, longitude: 12.373075, radius: 150}, attrs)

    [[id]] =
      rows(
        "INSERT INTO areas (user_id, name, latitude, longitude, radius, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, now(), now()) RETURNING id",
        [user_id, name, lat, lon, radius]
      )

    id
  end

  defp place!(user_id, lat, lon, lonlat \\ true) do
    [[id]] =
      rows(
        "INSERT INTO places (user_id, name, latitude, longitude, lonlat, created_at, updated_at) VALUES ($1, 'Place', $2, $3, NULL, now(), now()) RETURNING id",
        [user_id, lat, lon]
      )

    if lonlat,
      do:
        rows(
          "UPDATE places SET lonlat = ST_SetSRID(ST_MakePoint(#{lon}, #{lat}), 4326)::geography WHERE id = $1",
          [id]
        )

    id
  end

  defp visit!(user_id, attrs \\ %{}) do
    attrs =
      Map.merge(
        %{
          area_id: nil,
          place_id: nil,
          status: 0,
          detection_version: 1,
          name: "Detected",
          deleted_at: nil
        },
        Map.new(attrs)
      )

    [[id]] =
      rows(
        "INSERT INTO visits (user_id, area_id, place_id, status, detection_version, name, deleted_at, duration, started_at, ended_at, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, 60, $8::timestamp, $8::timestamp + interval '1 hour', now(), now()) RETURNING id",
        [
          user_id,
          attrs.area_id,
          attrs.place_id,
          attrs.status,
          attrs.detection_version,
          attrs.name,
          attrs.deleted_at,
          ~N[2026-06-01 10:00:00]
        ]
      )

    id
  end

  defp point!(user_id, visit_id, lat, lon) do
    rows(
      "INSERT INTO points (user_id, visit_id, lonlat, created_at, updated_at) VALUES ($1, $2, ST_SetSRID(ST_MakePoint(#{lon}, #{lat}), 4326)::geography, now(), now())",
      [user_id, visit_id]
    )
  end

  test "distance_m returns Geocoder's doubles bit for bit" do
    assert Areas.distance_m({52.520008, 13.404954}, {52.520908, 13.404954}) ==
             100.07543398040785

    assert Areas.distance_m({51.339695, 12.373075}, {51.3405, 12.3745}) ==
             133.45556000844886

    assert Areas.distance_m({-33.8688, 151.2093}, {-33.8697, 151.2101}) ==
             124.38070855255445

    assert Areas.distance_m({0.000001, 179.999999}, {0.000001, -179.999999}) ==
             0.22238985572889264

    assert Areas.distance_m({51.339695, 12.373075}, {51.339695, 12.373075}) == 0.0
  end

  test "labels visits whose centre lies inside the radius and renames only suggested machine visits",
       %{user_id: user_id} do
    area_id = area!(user_id)
    suggested = visit!(user_id, place_id: place!(user_id, 51.3405, 12.3745))

    confirmed =
      visit!(user_id,
        status: 1,
        detection_version: 1,
        name: "My spot",
        place_id: place!(user_id, 51.339695, 12.373075)
      )

    legacy =
      visit!(user_id,
        detection_version: nil,
        name: "Old",
        place_id: place!(user_id, 51.339695, 12.373075)
      )

    outside = visit!(user_id, place_id: place!(user_id, 51.3415, 12.373075))

    assert Areas.relabel(ScratchRepo, area_id) == :ok

    assert rows("SELECT area_id, name FROM visits WHERE id = $1", [suggested]) == [
             [area_id, "Leipzig"]
           ]

    assert rows("SELECT area_id, name FROM visits WHERE id = $1", [confirmed]) == [
             [area_id, "My spot"]
           ]

    assert rows("SELECT area_id, name FROM visits WHERE id = $1", [legacy]) == [[area_id, "Old"]]
    assert rows("SELECT area_id FROM visits WHERE id = $1", [outside]) == [[nil]]
  end

  test "point-backed visits use the centroid; no place and no points stays unlabelled; a (0,0) centre never matches",
       %{user_id: user_id} do
    area_id = area!(user_id)
    centroid = visit!(user_id)
    bare = visit!(user_id)
    zero = visit!(user_id)
    point!(user_id, centroid, 51.3396, 12.3730)
    point!(user_id, centroid, 51.3398, 12.37315)
    point!(user_id, zero, 0, 0)

    assert Areas.relabel(ScratchRepo, area_id) == :ok
    assert rows("SELECT area_id FROM visits WHERE id = $1", [centroid]) == [[area_id]]
    assert rows("SELECT area_id FROM visits WHERE id = $1", [bare]) == [[nil]]
    assert rows("SELECT area_id FROM visits WHERE id = $1", [zero]) == [[nil]]
  end

  test "place centres prefer lonlat over the decimal columns", %{user_id: user_id} do
    area_id = area!(user_id)
    place_id = place!(user_id, 51.429695, 12.373075)

    rows(
      "UPDATE places SET lonlat = ST_SetSRID(ST_MakePoint(12.373075, 51.339695), 4326)::geography WHERE id = $1",
      [place_id]
    )

    id = visit!(user_id, place_id: place_id)

    assert Areas.relabel(ScratchRepo, area_id) == :ok
    assert rows("SELECT area_id FROM visits WHERE id = $1", [id]) == [[area_id]]
  end

  test "never relabels attributed, tombstoned or declined visits", %{user_id: user_id} do
    area_id = area!(user_id)
    other = area!(user_id, %{name: "Other"})
    claimed = visit!(user_id, area_id: other, place_id: place!(user_id, 51.339695, 12.373075))

    tombstoned =
      visit!(user_id,
        deleted_at: ~N[2026-06-01 00:00:00],
        place_id: place!(user_id, 51.339695, 12.373075)
      )

    declined = visit!(user_id, status: 2, place_id: place!(user_id, 51.339695, 12.373075))

    assert Areas.relabel(ScratchRepo, area_id) == :ok
    assert rows("SELECT area_id FROM visits WHERE id = $1", [claimed]) == [[other]]
    assert rows("SELECT area_id FROM visits WHERE id = $1", [tombstoned]) == [[nil]]
    assert rows("SELECT area_id FROM visits WHERE id = $1", [declined]) == [[nil]]
  end

  test "a visit labelled by someone else after the batch was read keeps that label", %{
    user_id: user_id
  } do
    area_id = area!(user_id)
    other = area!(user_id, %{name: "Other"})
    id = visit!(user_id, place_id: place!(user_id, 51.339695, 12.373075))

    assert Areas.relabel(ScratchRepo, area_id,
             before_label: fn _ ->
               rows("UPDATE visits SET area_id = $1 WHERE id = $2", [other, id])
             end
           ) == :ok

    assert rows("SELECT area_id FROM visits WHERE id = $1", [id]) == [[other]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  test "each labelled batch commits with one visit_months_changed row", %{user_id: user_id} do
    area_id = area!(user_id)
    ids = for _ <- 1..3, do: visit!(user_id, place_id: place!(user_id, 51.339695, 12.373075))

    assert Areas.relabel(ScratchRepo, area_id, batch: 2) == :ok

    assert rows("SELECT payload->>'user_id' FROM phoenix.rails_commands ORDER BY id") == [
             [Integer.to_string(user_id)],
             [Integer.to_string(user_id)]
           ]

    assert rows("SELECT payload->'started_at' FROM phoenix.rails_commands ORDER BY id") == [
             [["2026-06-01T10:00:00.000000Z"]],
             [["2026-06-01T10:00:00.000000Z"]]
           ]

    assert rows("SELECT count(*) FROM visits WHERE id = ANY($1) AND area_id = $2", [ids, area_id]) ==
             [[3]]
  end

  test "a second run changes nothing and emits nothing", %{user_id: user_id} do
    area_id = area!(user_id)
    visit!(user_id, place_id: place!(user_id, 51.339695, 12.373075))

    assert Areas.relabel(ScratchRepo, area_id) == :ok
    assert Areas.relabel(ScratchRepo, area_id) == :ok
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[1]]
  end

  test "a deleted area or a soft-deleted user is :missing", %{user_id: user_id} do
    area_id = area!(user_id)
    rows("DELETE FROM areas WHERE id = $1", [area_id])
    assert Areas.relabel(ScratchRepo, area_id) == :missing

    area_id = area!(user_id)
    rows("UPDATE users SET deleted_at = now() WHERE id = $1", [user_id])
    assert Areas.relabel(ScratchRepo, area_id) == :missing
  end
end
