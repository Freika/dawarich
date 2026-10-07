defmodule Dawarich.A12f3bE14A1Test do
  use Dawarich.TracksCase

  alias Dawarich.Jobs.Ownership
  alias Dawarich.Tracks.{BoundaryWorker, ChunkWorker, DailyWorker, RangeWorker}

  @now ~U[2026-10-04 12:00:00.000000Z]
  @epoch DateTime.to_unix(@now)

  setup do
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    previous = Application.fetch_env!(:dawarich, :cable)
    Application.put_env(:dawarich, :cable, transport: :pg, bus: false)
    on_exit(fn -> Application.put_env(:dawarich, :cable, previous) end)

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

    for [payload] <-
          rows(
            "SELECT args FROM oban.oban_jobs WHERE worker=$1",
            [inspect(Dawarich.Tracks.NativeChangesWorker)]
          ),
        do: assert(Dawarich.Tracks.NativeChangesWorker.run(ScratchRepo, payload) == :ok)

    assert [[count]] = rows("SELECT count(*) FROM phoenix.cable_events")
    assert count > 0

    backfill!()
    realtime!()
    recalculate!()
    deduplicate!()
  end

  defp reset! do
    Dawarich.JobsCase.reset!(ScratchRepo)
    Ownership.put!(ScratchRepo, "command:tracks.generate_range", :oban)
  end

  defp backfill! do
    reset!()
    Ownership.put!(ScratchRepo, "command:tracks.backfill", :oban)
    user = user!()
    stamps = [@epoch - 172_800, @epoch - 172_740]
    [first, last] = stamps
    point!(user.id, first, 12.3731, 51.3397)
    point!(user.id, last, 12.3741, 51.3407)

    assert {:inserted, range} =
             Dawarich.Tracks.BackfillCommands.put(ScratchRepo, user.id, stamps,
               now: @now,
               time_zone: "Berlin"
             )

    assert [[payload, due]] = rows("SELECT payload, scheduled_at FROM public.job_outbox")
    assert due == DateTime.add(@now, 60)
    assert {:ok, args} = Dawarich.Tracks.BackfillWorker.args_from_command(1, payload)
    assert Dawarich.Tracks.BackfillWorker.run(ScratchRepo, oban(), args, now: due) == :ok

    assert [[generation_args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker = $1", [inspect(RangeWorker)])

    assert generation_args["event_id"] == range.cycle_id
    assert generation_args["untracked_only"]
    finish!(generation_args)
    assert rows("SELECT count(*) FROM tracks") == [[1]]
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
  end

  defp finish!(args) do
    assert RangeWorker.run(ScratchRepo, oban(), args) == :ok

    for [chunk] <- chunk_jobs(args["event_id"]),
        do: assert(ChunkWorker.run(ScratchRepo, oban(), chunk) == :ok)

    assert BoundaryWorker.run(ScratchRepo, oban(), %{
             "generation_id" => args["event_id"],
             "poll_count" => 0
           }) == :ok

    assert [["completed" | _]] = generation(args["event_id"])
  end

  defp realtime! do
    reset!()
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)
    %{call: [%{"now" => now}], expected: expected} = TracksFixtures.load!(ScratchRepo, "realtime")
    rows("UPDATE users SET status = 2 WHERE id = 1")

    assert Dawarich.Tracks.RealtimeWorker.run(
             ScratchRepo,
             oban(),
             %{"user_id" => 1, "event_id" => Ecto.UUID.generate()},
             now: now
           ) == :ok

    assert actual_tracks() == expected_tracks(expected)
    assert actual_segments() == expected_segments(expected)
    assert point_identities() == expected_point_identities(expected)
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
  end

  defp recalculate! do
    reset!()
    %{call: calls, expected: expected} = TracksFixtures.load!(ScratchRepo, "recalculate")

    for %{"track_id" => id} <- calls,
        do:
          assert(
            Dawarich.Tracks.RecalculateWorker.run(ScratchRepo, oban(), %{"track_id" => id}) == :ok
          )

    assert actual_tracks() == expected_tracks(expected)
    assert point_identities() == expected_point_identities(expected)
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
  end

  defp deduplicate! do
    reset!()
    user = user!()
    loser = track!(user.id, "phone", @epoch - 600, @epoch - 540)
    winner = track!(user.id, "watch", @epoch - 600, @epoch - 540)
    point = point!(user.id, @epoch - 600, 12.3731, 51.3397, track_id: loser)
    assert Dawarich.ReleaseOperations.TracksDedup.run(ScratchRepo, user.id) == :ok
    assert rows("SELECT id FROM tracks") == [[winner]]
    assert rows("SELECT track_id FROM points WHERE id = $1", [point]) == [[nil]]
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
  end
end
