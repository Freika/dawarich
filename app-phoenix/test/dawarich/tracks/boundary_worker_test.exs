defmodule Dawarich.Tracks.BoundaryWorkerTest do
  use Dawarich.TracksCase

  alias Dawarich.Tracks.{BoundaryWorker, PerUserLock, Settings}

  defp look(id, opts \\ []),
    do:
      BoundaryWorker.run(
        ScratchRepo,
        oban(),
        %{"generation_id" => id, "poll_count" => 0},
        [lock: [timeout_ms: 200]] ++ opts
      )

  defp hold_lock!(user_id) do
    rails = rails_redis!()
    Redix.command!(rails, ["SET", PerUserLock.key(user_id), "rails-token", "PX", "60000"])
    rails
  end

  test "completes after all chunks under the lock" do
    %{call: [call], expected: expected} = TracksFixtures.load!(ScratchRepo, "range_dst")
    user = Settings.load!(ScratchRepo, 1)
    known = identities()

    id = generate_chunks!(user, call)
    known = Map.merge(known, identities())
    chunk_tracks = actual_tracks()
    assert [["running", 3, 3, 0, 0, nil]] = generation(id)

    rails = hold_lock!(user.id)
    assert look(id) == {:error, :lock_busy}
    assert actual_tracks() == chunk_tracks
    assert [["running", 3, 3, 0, 0, nil]] = generation(id)

    Redix.command!(rails, ["DEL", PerUserLock.key(user.id)])
    assert look(id) == :ok

    assert generation(id) == [["completed", 3, 3, 0, 0, nil]]
    assert actual_tracks() == expected_tracks(expected)
    assert point_identities() == expected_point_identities(expected)
    assert actual_segments() == expected_segments(expected)

    assert Enum.sort(events(Map.merge(known, identities()))) ==
             Enum.sort(expected_events(expected))

    assert look(id) == :ok
    assert generation(id) == [["completed", 3, 3, 0, 0, nil]]
  end

  test "a held lock on the final attempt fails the generation" do
    %{call: [call]} = TracksFixtures.load!(ScratchRepo, "range_dst")
    id = generate_chunks!(Settings.load!(ScratchRepo, 1), call)
    hold_lock!(1)

    assert look(id, attempt: 4, max_attempts: 5) == {:error, :lock_busy}
    assert [["running" | _]] = generation(id)

    assert look(id, attempt: 5, max_attempts: 5) == {:error, :lock_busy}
    assert [["failed", 3, 3, 0, 0, error]] = generation(id)
    assert error =~ "could not acquire lock for user_id=1"
  end
end
