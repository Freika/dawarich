defmodule Dawarich.A12f3bE14A1Test do
  use Dawarich.TracksCase

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Tracks.{BoundaryWorker, ChunkWorker, DailyWorker, RangeWorker}

  @now ~U[2026-10-04 12:00:00.000000Z]
  @epoch DateTime.to_unix(@now)

  setup do
    start_supervised!(hd(Dawarich.Redis.child_specs()))

    for key <- ~w(cron:daily_track_generation_job command:tracks.generate_range),
        do: Ownership.put!(ScratchRepo, key, :oban)

    :ok
  end

  @tag a12f3b_case: "E14A1a"
  test "E14A1 native source shapes reach their terminal effects" do
    for zone <- ["Tokyo", "Asia/Tokyo"] do
      user = user!(%{"timezone" => zone})
      rows("UPDATE users SET status = 1, points_count = 2 WHERE id = $1", [user.id])
      point!(user.id, @epoch - 600, 12.3731, 51.3397)
      point!(user.id, @epoch - 540, 12.3741, 51.3407)
    end

    assert DailyWorker.run(ScratchRepo, oban(), @epoch, now: @now) == :ok

    jobs =
      rows("SELECT args FROM oban.oban_jobs WHERE worker = $1 ORDER BY id", [inspect(RangeWorker)])

    assert length(jobs) == 2

    for [args] <- jobs do
      assert args["time_zone"] == "Asia/Tokyo"
      assert args["start_at"] == iso(@epoch - 600)
      assert args["end_at"] == iso(@epoch)
      assert args["mode"] == "daily"
      assert args["event_id"] == DailyWorker.event_id(@epoch, args["user_id"])
      assert RangeWorker.run(ScratchRepo, oban(), args) == :ok

      for [chunk] <- chunk_jobs(args["event_id"]),
          do: assert(ChunkWorker.run(ScratchRepo, oban(), chunk) == :ok)

      assert BoundaryWorker.run(ScratchRepo, oban(), %{
               "generation_id" => args["event_id"],
               "poll_count" => 0
             }) == :ok

      assert [["completed", 1, 1, 0, 0, nil]] = generation(args["event_id"])
    end

    assert rows("SELECT count(*) FROM tracks") == [[2]]
    assert rows("SELECT count(*) FROM points WHERE track_id IS NULL") == [[0]]
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
  end
end
