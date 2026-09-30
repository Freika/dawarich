defmodule Dawarich.Tracks.BoundaryTest do
  use Dawarich.TracksCase, async: true, group: :scratch_db

  alias Dawarich.Tracks.{Boundary, Builder, MetadataRefresher, Points, Settings}

  test "boundary resolution, reabsorption and metadata refresh reproduce Rails" do
    %{call: [call], expected: expected} = TracksFixtures.load!(ScratchRepo, "range_dst")
    user = Settings.load!(ScratchRepo, 1)
    known = identities()

    generate_chunks!(user, call)
    known = Map.merge(known, identities())

    assert Boundary.resolve(ScratchRepo, user) == 1
    refresh = MetadataRefresher.run(ScratchRepo, user)

    assert actual_tracks() == expected_tracks(expected)
    assert point_identities() == expected_point_identities(expected)
    assert actual_segments() == expected_segments(expected)

    assert Enum.sort(events(Map.merge(known, identities()))) ==
             Enum.sort(expected_events(expected))

    assert %{refreshed: 1, skipped: 0, reasons: [], sample_ids: []} = refresh

    assert expected["track_metadata_refresh"] == %{
             "refreshed" => 1,
             "skipped" => 0,
             "reasons" => %{},
             "sample_ids" => []
           }
  end

  for {tracker_id, merges} <- [{"  ", 0}, {"device-w", 1}] do
    @tracker_id tracker_id
    @merges merges

    test "a blank tracker id uses the route gap, not the same-tracker gap: #{inspect(tracker_id)}" do
      user = user!()
      t = 1_790_300_000

      first = [
        point!(user.id, t, 12.3731, 51.3397, tracker_id: @tracker_id),
        point!(user.id, t + 60, 12.3731, 51.3400, tracker_id: @tracker_id)
      ]

      second = [
        point!(user.id, t + 600, 12.3731, 51.3490, tracker_id: @tracker_id),
        point!(user.id, t + 660, 12.3731, 51.3493, tracker_id: @tracker_id)
      ]

      for ids <- [first, second] do
        points =
          Points.load_chunk(ScratchRepo, user.id, t, t + 660,
            untracked_only: false,
            import_id: nil
          )

        run = Enum.filter(points, &(&1.id in ids))

        {:ok, _} =
          Builder.create_track!(ScratchRepo, user, run, 100.0, skip_segment_detection: true)
      end

      assert Boundary.resolve(ScratchRepo, user) == @merges
      assert rows("SELECT count(*) FROM tracks WHERE user_id = $1", [user.id]) == [[2 - @merges]]
    end
  end
end
