defmodule Dawarich.Tracks.BackfillCommandsTest do
  use Dawarich.JobsCase, async: false

  import Dawarich.LockRace
  alias Dawarich.Ingest.Intake
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Tracks.{BackfillCommands, DailyWorker, RangeWorker}

  @now ~U[2026-10-04 12:00:00.000000Z]
  @epoch DateTime.to_unix(@now)

  setup do
    start_oban(__MODULE__)
    previous = System.get_env("SELF_HOSTED")

    on_exit(fn ->
      if previous,
        do: System.put_env("SELF_HOSTED", previous),
        else: System.delete_env("SELF_HOSTED")
    end)

    :ok
  end

  test "native ingest rolls range and publication back with failed intake" do
    user!(1, %{"timezone" => "Tokyo"})
    Ownership.put!(ScratchRepo, "command:tracks.backfill", :oban)
    input = Intake.prepare([%{lonlat: "POINT(1 1)", timestamp: @epoch - 100_000}], 1)
    fail = fn :commands -> ScratchRepo.query!("SELECT 1 / 0", [], log: false) end

    assert_raise Postgrex.Error, fn ->
      Intake.write(input, 1, repo: ScratchRepo, now: @now, time_zone: "Europe/Berlin", hook: fail)
    end

    assert rows("SELECT count(*) FROM phoenix.track_backfill_ranges") == [[0]]
    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]
    assert rows("SELECT count(*) FROM points WHERE user_id = 1") == [[1]]
    assert rows("SELECT points_count FROM users WHERE id = 1") == [[0]]
    assert rows("SELECT kind FROM phoenix.rails_commands ORDER BY id") == [["points.tile_epoch"]]
    assert [_] = Intake.write(input, 1, repo: ScratchRepo, now: @now, time_zone: "Europe/Berlin")
    assert [[payload, due]] = rows("SELECT payload, scheduled_at FROM public.job_outbox")
    assert payload["time_zone"] == "Europe/Berlin"
    assert due == DateTime.add(@now, 60)

    assert [[payload["cycle_id"]]] ==
             rows("SELECT cycle_id::text FROM phoenix.track_backfill_ranges")

    refute ["tracks.backfill"] in rows("SELECT kind FROM phoenix.rails_commands")
    assert [_] = Intake.write(input, 1, repo: ScratchRepo, now: @now)
    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]
    Ownership.put!(ScratchRepo, "command:tracks.backfill", :sidekiq)
    assert [_] = Intake.write(input, 1, repo: ScratchRepo, now: @now)

    assert [[reverse]] =
             rows("SELECT payload FROM phoenix.rails_commands WHERE kind = 'tracks.backfill'")

    assert reverse["time_zone"] == "Asia/Tokyo"
    assert reverse["timestamps"] == [@epoch - 100_000, @epoch - 100_000]
  end

  test "daily bootstrap uses selected backfill owner at the existing size boundary" do
    System.put_env("SELF_HOSTED", "false")
    Ownership.put!(ScratchRepo, "cron:daily_track_generation_job", :oban)
    Ownership.put!(ScratchRepo, "command:tracks.generate_range", :oban)
    Ownership.put!(ScratchRepo, "command:tracks.throttled_backfill", :oban)
    user!(1, %{"timezone" => "Tokyo"})
    user!(2, %{"timezone" => "Tokyo"})
    user!(3, %{}, 0)
    user!(4, %{})

    for {id, count} <- [{1, 100_000}, {2, 100_001}] do
      rows(
        "INSERT INTO points (user_id, timestamp, created_at, updated_at) SELECT $1, $2::bigint + g, now(), now() FROM generate_series(1, $3::int) AS g",
        [id, @epoch - 200_000, count]
      )

      rows("UPDATE users SET points_count = $2 WHERE id = $1", [id, count])
    end

    rows(
      "INSERT INTO points (user_id, timestamp, created_at, updated_at) VALUES (3, $1, now(), now()), (4, $1, now(), now())",
      [@epoch - 10_000]
    )

    rows("UPDATE users SET points_count = 1 WHERE id = 3")
    assert DailyWorker.run(ScratchRepo, __MODULE__, @epoch, now: @now) == :ok

    assert rows("SELECT user_id, time_zone FROM phoenix.track_backfill_walks") == [
             [2, "Asia/Tokyo"]
           ]

    assert [[%{"user_id" => 2, "cursor_timestamp" => nil, "time_zone" => "Asia/Tokyo"}]] =
             rows(
               "SELECT payload FROM public.job_outbox WHERE command_type = 'tracks.throttled_backfill'"
             )

    assert rows("SELECT (args->>'user_id')::int FROM oban.oban_jobs WHERE worker = $1", [
             inspect(RangeWorker)
           ]) == [[1]]

    assert DailyWorker.run(ScratchRepo, __MODULE__, @epoch, now: @now) == :ok
    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]
    Ownership.put!(ScratchRepo, "command:tracks.throttled_backfill", :sidekiq)
    assert DailyWorker.run(ScratchRepo, __MODULE__, @epoch, now: @now) == :ok

    assert [[%{"user_id" => 2, "time_zone" => "Asia/Tokyo"}]] =
             rows(
               "SELECT payload FROM phoenix.rails_commands WHERE kind = 'tracks_throttled_backfill'"
             )

    rows("TRUNCATE oban.oban_jobs")
    System.put_env("SELF_HOSTED", "true")
    assert DailyWorker.run(ScratchRepo, __MODULE__, @epoch, now: @now) == :ok

    assert rows(
             "SELECT (args->>'user_id')::int FROM oban.oban_jobs WHERE worker = $1 ORDER BY id",
             [inspect(RangeWorker)]
           ) == [[1], [2]]

    System.put_env("SELF_HOSTED", "false")

    rows(
      "INSERT INTO tracks (user_id, start_at, end_at, original_path, created_at, updated_at) VALUES (2, to_timestamp($1::bigint), to_timestamp($2::bigint), ST_GeomFromText('LINESTRING(1 1, 2 2)', 4326), now(), now())",
      [@epoch - 300_000, @epoch - 150_000]
    )

    rows("TRUNCATE oban.oban_jobs")
    assert DailyWorker.run(ScratchRepo, __MODULE__, @epoch, now: @now) == :ok

    assert rows(
             "SELECT (args->>'user_id')::int FROM oban.oban_jobs WHERE worker = $1 ORDER BY id",
             [inspect(RangeWorker)]
           ) == [[1], [2]]
  end

  test "owner release waits for producer transaction and preserves one accepted step" do
    Ownership.put!(ScratchRepo, "command:tracks.backfill", :oban)
    parent = self()

    holder =
      hold(fn ->
        assert {:inserted, range} =
                 BackfillCommands.put(ScratchRepo, 1, [@epoch - 100_000],
                   now: @now,
                   time_zone: "Berlin"
                 )

        send(parent, {:cycle, range.cycle_id})
      end)

    assert_receive {:cycle, cycle}
    assert rows("SELECT count(*) FROM public.job_outbox") == [[0]]

    release =
      Task.async(fn -> Ownership.put!(ScratchRepo, "command:tracks.backfill", :sidekiq) end)

    assert settle(release, "INSERT INTO phoenix.job_owners%") == :blocked
    commit(holder)
    assert Task.await(release) == :ok
    assert rows("SELECT event_id::text FROM public.job_outbox") == [[cycle]]

    assert rows("SELECT cycle_id::text, time_zone FROM phoenix.track_backfill_ranges") == [
             [cycle, "Europe/Berlin"]
           ]

    assert BackfillCommands.put(ScratchRepo, 1, [@epoch - 200_000],
             now: @now,
             time_zone: "Asia/Tokyo"
           ) == :ok

    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]

    assert [["tracks.backfill", %{"user_id" => 1, "time_zone" => "Asia/Tokyo"}]] =
             rows("SELECT kind, payload FROM phoenix.rails_commands")

    assert rows("SELECT cycle_id::text FROM phoenix.track_backfill_ranges") == [[cycle]]
  end

  defp user!(id, settings, status \\ 1) do
    rows(
      "INSERT INTO users (id, email, settings, status, points_count, created_at, updated_at) VALUES ($1, $2, $3, $4, 0, now(), now())",
      [id, "backfill-#{id}@example.test", settings, status]
    )
  end
end
