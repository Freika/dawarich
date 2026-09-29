defmodule Dawarich.Tracks.GenerationParityTest do
  use Dawarich.TracksCase

  alias Dawarich.Tracks.{Boundary, MetadataRefresher, Settings}

  for name <- ~w(range_kept range_orphans range_two_trackers range_untracked_only range_q2) do
    @name name

    test "chunks, boundary resolution and refresh reproduce Rails: #{name}" do
      %{call: calls, expected: expected} = TracksFixtures.load!(ScratchRepo, @name)
      user = Settings.load!(ScratchRepo, 1)

      known =
        Enum.reduce(calls, identities(), fn call, known ->
          generate_chunks!(user, call)
          known = Map.merge(known, identities())
          Boundary.resolve(ScratchRepo, user)
          MetadataRefresher.run(ScratchRepo, user)
          Map.merge(known, identities())
        end)

      assert actual_tracks() == expected_tracks(expected)
      assert point_identities() == expected_point_identities(expected)
      assert actual_segments() == expected_segments(expected)
      assert Enum.sort(events(known)) == Enum.sort(expected_events(expected))
    end
  end
end
