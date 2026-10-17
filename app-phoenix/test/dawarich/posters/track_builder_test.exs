defmodule Dawarich.Posters.TrackBuilderTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.Posters.{Geometry, TrackBuilder}
  alias Dawarich.Test.{ApiGolden, FrameSeeds}

  @tag mutation: "gap"
  test "point source excludes anomalies out of range timestamps and foreign rows and splits only gaps over one hour" do
    state = load("points_gap_boundaries")
    user = seed(state)
    for row <- state["points"], do: ApiGolden.insert!("points", row)
    foreign = FrameSeeds.user!(97102)
    row = hd(state["points"]) |> Map.put("id", 97901) |> Map.put("user_id", foreign.id)
    ApiGolden.insert!("points", row)
    assert TrackBuilder.build(user.id, state["before"]["settings"]) == state["track"]
    assert length(state["track"]["coordinates"]) == 2
    assert Enum.map(state["track"]["coordinates"], &length/1) == [3, 2]
  end

  @tag mutation: "null-lonlat"
  test "in range null lonlat retains captured Rails geometry and failure behavior" do
    state = load("null_lonlat")
    user = seed(state)
    for row <- state["points"], do: ApiGolden.insert!("points", row)
    track = TrackBuilder.build(user.id, state["before"]["settings"])
    assert track == state["track"]
    assert hd(hd(track["coordinates"])) == [nil, nil]
    assert_raise ArgumentError, fn -> Geometry.intersects?(track, state["before"]["settings"]) end
    assert state["geometry"]["intersection_error"] == "NoMethodError"
    assert state["after"]["status"] == 3
    assert state["attachments"] == []
  end

  @tag mutation: "path"
  test "track source uses original overlapping paths and drops singleton segments" do
    state = load("overlapping_tracks_theme_basename")
    user = seed(state)
    for row <- state["tracks"], do: ApiGolden.insert!("tracks", row)
    assert TrackBuilder.build(user.id, state["before"]["settings"]) == state["track"]

    assert TrackBuilder.geometry([[], [[1, 2]], [[1, 2], [3, 4]]]) ==
             %{"type" => "MultiLineString", "coordinates" => [[[1, 2], [3, 4]]]}

    Repo.query!(
      "UPDATE tracks SET original_path=ST_GeomFromText('LINESTRING(1 2,1.002 2.003,1.005 2)',4326) WHERE id=$1",
      [97401]
    )

    first = TrackBuilder.build(user.id, state["before"]["settings"])["coordinates"] |> hd()
    assert first == [[1.0, 2.0], [1.002, 2.003], [1.005, 2.0]]
    foreign = FrameSeeds.user!(97102)
    row = hd(state["tracks"]) |> Map.put("id", 97902) |> Map.put("user_id", foreign.id)
    ApiGolden.insert!("tracks", row)
    assert length(TrackBuilder.build(user.id, state["before"]["settings"])["coordinates"]) == 2
  end

  defp seed(state), do: FrameSeeds.user!(state["actor_id"])
  defp load(name), do: File.read!("test/fixtures/posters/" <> name <> ".json") |> Jason.decode!()
end
