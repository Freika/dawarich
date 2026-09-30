defmodule Dawarich.Tracks.RecalculatorTest do
  use Dawarich.TracksCase, async: true, group: :scratch_db

  alias Dawarich.Tracks.Recalculator

  test "reproduces RecalculateJob" do
    %{call: calls, expected: expected} = TracksFixtures.load!(ScratchRepo, "recalculate")
    known = identities()
    before = rows("SELECT id, lock_version, updated_at FROM tracks ORDER BY id")

    outcomes = for %{"track_id" => id} <- calls, do: Recalculator.run(ScratchRepo, id)

    assert [{:recalculated, _}, {:recalculated, _}, :destroyed] = outcomes
    assert actual_tracks() == expected_tracks(expected)
    assert point_identities() == expected_point_identities(expected)
    assert rows("SELECT count(*) FROM track_segments") == [[length(expected["track_segments"])]]
    assert events(known) == expected_events(expected)

    [[1, 0, changed_at], [2, 0, unchanged_at], [3, 0, _]] = before

    assert [[1, 1, changed_after], [2, 0, ^unchanged_at]] =
             rows("SELECT id, lock_version, updated_at FROM tracks ORDER BY id")

    assert NaiveDateTime.compare(changed_after, changed_at) == :gt
  end

  test "segment geometry follows GeometryRecalculator" do
    TracksFixtures.load!(ScratchRepo, "recalculate")

    for {start_at, end_at, start_index, end_index} <- [
          {1_788_242_400, 1_788_243_000, nil, nil},
          {nil, nil, 2, 3},
          {nil, nil, 3, 5}
        ] do
      rows(
        "INSERT INTO track_segments (track_id, transportation_mode, start_at, end_at, start_index, end_index, " <>
          "created_at, updated_at) VALUES (1, 2, to_timestamp($1::bigint), to_timestamp($2::bigint), $3, $4, now(), now())",
        [start_at, end_at, start_index, end_index]
      )
    end

    assert {:recalculated, _} = Recalculator.run(ScratchRepo, 1)

    assert rows(
             "SELECT distance, duration, avg_speed, max_speed, ST_AsText(path) FROM track_segments ORDER BY id"
           ) == [
             [
               157,
               600,
               0.94,
               0.9432925712736453,
               "LINESTRING(12.3731 51.3397,12.3739 51.3402,12.3747 51.3407)"
             ],
             [79, 600, 0.47, 0.47164114329390505, "LINESTRING(12.3747 51.3407,12.3755 51.3412)"],
             [0, 0, 0.0, 0.0, nil]
           ]
  end

  test "a missing track is left alone" do
    assert Recalculator.run(ScratchRepo, 424_242) == :missing
    assert tracks_changed() == []
  end
end
