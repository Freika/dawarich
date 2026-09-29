defmodule Dawarich.Tracks.RealtimeParityTest do
  use Dawarich.TracksCase

  alias Dawarich.Tracks.{Boundary, Builder, Merger, Points, Settings}

  test "segments, merge with the preceding track and reabsorption reproduce IncrementalGenerator" do
    %{call: [%{"now" => now}], expected: expected} = TracksFixtures.load!(ScratchRepo, "realtime")
    user = Settings.load!(ScratchRepo, 1)
    known = identities()

    segments =
      Points.realtime_segments(
        ScratchRepo,
        user.id,
        now - 6 * 3600,
        now,
        Settings.minutes_between_routes(user),
        Settings.meters_between_routes(user)
      )

    known =
      Enum.reduce(segments, known, fn segment, known ->
        {:ok, track} =
          Builder.create_track!(ScratchRepo, user, segment.points, segment.distance,
            tracker_id: segment.tracker_id
          )

        known = Map.merge(known, identities())
        Merger.merge_into_preceding(ScratchRepo, user, track)
        Map.merge(known, identities())
      end)

    Boundary.resolve(ScratchRepo, user, now: now)
    known = Map.merge(known, identities())

    assert length(segments) == 2
    assert actual_tracks() == expected_tracks(expected)
    assert point_identities() == expected_point_identities(expected)
    assert actual_segments() == expected_segments(expected)
    assert Enum.sort(events(known)) == Enum.sort(expected_events(expected))
  end
end
