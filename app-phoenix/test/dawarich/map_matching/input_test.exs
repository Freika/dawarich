defmodule Dawarich.MapMatching.InputTest do
  use Dawarich.TracksCase, async: true, group: :tracks_db
  alias Dawarich.MapMatching.Input

  setup do
    user = user!()
    track = track!(user.id, nil, 100, 130)

    ids =
      for time <- [130, 100, 110, 120],
          do: point!(user.id, time, 13.4 + time / 10000, 52.5, track_id: track)

    rows("UPDATE points SET accuracy = 5 WHERE track_id = $1", [track])
    %{track: track, ids: ids, user: user}
  end

  defp segment(track, mode, first, last, times \\ false) do
    anchors = if times, do: "start_at, end_at", else: "start_index, end_index"
    values = if times, do: "to_timestamp($3::bigint), to_timestamp($4::bigint)", else: "$3, $4"

    [[id]] =
      rows(
        "INSERT INTO track_segments (track_id, transportation_mode, #{anchors}, created_at, updated_at) VALUES ($1, $2, #{values}, now(), now()) RETURNING id",
        [track, mode, first, last]
      )

    id
  end

  test "anomaly points are excluded", %{track: track} do
    rows("UPDATE points SET anomaly = true WHERE track_id = $1 AND timestamp = 110", [track])
    rows("UPDATE points SET anomaly = false WHERE track_id = $1 AND timestamp = 120", [track])
    input = Input.load(ScratchRepo, track)
    assert Enum.map(input.points, & &1.timestamp) == [100, 120, 130]
    assert Enum.map(input.points, & &1.accuracy) == [5.0, 5.0, 5.0]
  end

  test "segments are ordered by source position", %{track: track} do
    second = segment(track, 7, 120, 130, true)
    first = segment(track, 2, 100, 120, true)
    input = Input.load(ScratchRepo, track)
    assert Enum.map(Input.portions(input), & &1.key) == ["segment:#{first}", "segment:#{second}"]
    assert Enum.map(input.segment_fingerprint, & &1.mode) == ["walking", "train"]

    assert Enum.map(input.portions, fn p -> Enum.map(p.points, & &1.timestamp) end) == [
             [100, 110, 120],
             [120, 130]
           ]

    assert Input.eligible?(input)
  end

  test "uncovered edges retain original fallback and index anchors", %{track: track} do
    segment(track, 4, 0, 1)
    segment(track, 5, 2, 3)
    input = Input.load(ScratchRepo, track)
    assert Enum.map(input.portions, & &1.atlas_mode) == ["bicycle", nil, "auto"]
    assert Enum.map(input.portions, &{&1.start_index, &1.end_index}) == [{0, 1}, {1, 2}, {2, 3}]
    assert Enum.map(input.portions, &length(&1.points)) == [2, 2, 2]
  end

  test "a segment with fewer than 2 points is not eligible", %{track: track} do
    segment(track, 2, 0, 0)
    rows("DELETE FROM points WHERE track_id = $1 AND timestamp <> 100", [track])
    input = Input.load(ScratchRepo, track)
    refute Input.eligible?(input)
    assert input.portions == []
    portion = struct(Input.Portion, %{atlas_mode: "pedestrian", points: input.points})
    refute Input.eligible?(portion)
  end
end
