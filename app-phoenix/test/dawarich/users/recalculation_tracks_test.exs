defmodule Dawarich.Users.RecalculationTracksTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Tracks.{Generation, PerUserLock}
  alias Dawarich.Users.{Recalculation, RecalculationPeriod, RecalculationTracks}

  test "starts stable range generations and returns before asynchronous chunks" do
    source = Fixtures.case!("user_specific")
    Fixtures.load!(ScratchRepo, source)
    oban = :recalculation_tracks
    start_oban(oban)
    state = %{user_id: 170_101, years: [2025, 2024], zone: "Europe/Berlin"}
    args = %{"source_job_id" => source["job"]["job_id"], "job_queue" => "low_priority"}
    assert RecalculationTracks.run(ScratchRepo, oban, state, args) == :ok
    id = RecalculationPeriod.event_id(args["source_job_id"], 2025)

    assert %{status: "running", completed_chunks: 0, low_priority: true, total_chunks: count} =
             Generation.get(ScratchRepo, id)

    assert count == 4
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[count + 1]]
    assert rows("SELECT DISTINCT priority FROM oban.oban_jobs") == [[3]]

    assert rows("SELECT mode,untracked_only,import_id FROM phoenix.track_generations") == [
             ["bulk", false, nil]
           ]

    assert rows("SELECT count(*) FROM phoenix.job_owners") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.leases") == [[0]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[1]]
    assert RecalculationTracks.run(ScratchRepo, oban, state, args) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[count + 1]]
    fresh = Map.put(args, "source_job_id", Ecto.UUID.generate())
    assert RecalculationTracks.run(ScratchRepo, oban, state, fresh) == :ok
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[2]]
  end

  test "propagates shared track lock contention without announcing success" do
    source = Fixtures.case!("user_specific")
    Fixtures.load!(ScratchRepo, source)
    oban = :recalculation_tracks_busy
    start_oban(oban)
    hold_lease!(ScratchRepo, PerUserLock.key(170_101), "rails-holder")
    args = %{"user_id" => 170_101, "year" => 2025, "source_job_id" => source["job"]["job_id"]}

    options = [
      now: ~U[2026-10-03 12:00:00Z],
      env: %{"SELF_HOSTED" => "false"},
      range_opts: [lock: [timeout_ms: 0]]
    ]

    assert Recalculation.run(ScratchRepo, oban, args, options) == {:error, :lock_busy}
    assert rows("SELECT count(*) FROM stats") != [[0]]
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[0]]
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    assert lease_holders(ScratchRepo, PerUserLock.key(170_101)) == [["rails-holder"]]
  end
end
