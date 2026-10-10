defmodule Dawarich.Tracks.BoundaryWorkerTest do
  use Dawarich.TracksCase, async: true, group: :tracks_db

  alias Dawarich.Tracks.{BoundaryWorker, ChunkWorker, PerUserLock, RangeWorker, Settings}

  defp look(id, opts \\ []),
    do:
      BoundaryWorker.run(
        ScratchRepo,
        oban(),
        %{"generation_id" => id, "poll_count" => 0},
        [lock: [timeout_ms: 0]] ++ opts
      )

  defp hold_lock!(user_id),
    do: Dawarich.JobsCase.hold_lease!(ScratchRepo, PerUserLock.key(user_id), "rails-token")

  @tag a12f3b_case: "E14Ba"
  test "completes after all chunks under the lock" do
    %{call: [call], expected: expected} = TracksFixtures.load!(ScratchRepo, "range_dst")
    user = Settings.load!(ScratchRepo, 1)
    known = identities()

    id = generate_chunks!(user, call)
    known = Map.merge(known, identities())
    chunk_tracks = actual_tracks()
    assert [["running", 3, 3, 0, 0, nil]] = generation(id)
    assert Dawarich.Jobs.Drain.status(ScratchRepo).counts.unfinished_generations == 1

    hold_lock!(user.id)
    assert look(id) == {:error, :lock_busy}
    assert actual_tracks() == chunk_tracks
    assert [["running", 3, 3, 0, 0, nil]] = generation(id)

    rows("DELETE FROM phoenix.leases WHERE name = $1", [PerUserLock.key(user.id)])
    assert look(id) == :ok

    assert generation(id) == [["completed", 3, 3, 0, 0, nil]]
    assert Dawarich.Jobs.Drain.status(ScratchRepo).counts.unfinished_generations == 0
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

  test "the last chunk landing between the load and the poll still finishes" do
    user = user!()
    t = 1_790_000_000
    point!(user.id, t, 12.3731, 51.3397)
    point!(user.id, t + 60, 12.3741, 51.3407)
    id = Ecto.UUID.generate()

    :ok =
      RangeWorker.run(ScratchRepo, oban(), %{
        "event_id" => id,
        "user_id" => user.id,
        "start_at" => iso(t - 3_600),
        "end_at" => iso(t + 3_600),
        "time_zone" => "UTC",
        "mode" => "bulk",
        "untracked_only" => true,
        "import_id" => nil,
        "low_priority" => false
      })

    land_last_chunk = fn :loaded ->
      [[args]] = chunk_jobs(id)
      :ok = ChunkWorker.run(ScratchRepo, oban(), args)
    end

    assert look(id, hook: land_last_chunk) == :ok
    assert generation(id) == [["completed", 1, 1, 0, 0, nil]]
    assert rows("SELECT count(*) FROM tracks") == [[1]]

    assert rows(
             "SELECT count(*) FROM oban.oban_jobs WHERE worker = $1 AND (args->>'poll_count')::int > 0",
             [inspect(BoundaryWorker)]
           ) == [[0]]
  end

  test "a user deleted before the finish fails the generation" do
    %{call: [call]} = TracksFixtures.load!(ScratchRepo, "range_dst")
    id = generate_chunks!(Settings.load!(ScratchRepo, 1), call)
    rows("UPDATE users SET deleted_at = now() WHERE id = 1")

    assert look(id) == :ok
    assert generation(id) == [["failed", 3, 3, 0, 0, "User 1 not found"]]
  end

  test "a database error while taking the lock raises, and on the final attempt fails the generation" do
    %{call: [call]} = TracksFixtures.load!(ScratchRepo, "range_dst")
    id = generate_chunks!(Settings.load!(ScratchRepo, 1), call)
    rows("ALTER TABLE phoenix.leases RENAME TO leases_away")
    on_exit(fn -> rows("ALTER TABLE phoenix.leases_away RENAME TO leases") end)

    assert_raise Postgrex.Error, fn -> look(id, attempt: 4, max_attempts: 5) end
    assert [["running" | _]] = generation(id)

    assert_raise Postgrex.Error, fn -> look(id, attempt: 5, max_attempts: 5) end
    assert [["failed", 3, 3, 0, 0, error]] = generation(id)
    assert error =~ ~s(relation "phoenix.leases" does not exist)
  end

  test "the final attempt is never killed by the job timeout" do
    assert BoundaryWorker.timeout(%Oban.Job{attempt: 4, max_attempts: 5}) == :timer.minutes(30)
    assert BoundaryWorker.timeout(%Oban.Job{attempt: 5, max_attempts: 5}) == :infinity
  end
end
