defmodule Dawarich.Tracks.BoundaryTest do
  use Dawarich.TracksCase

  alias Dawarich.Tracks.{Boundary, MetadataRefresher, Settings}

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
end
