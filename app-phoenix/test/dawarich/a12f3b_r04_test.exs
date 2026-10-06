defmodule Dawarich.A12f3bR04Test do
  use Dawarich.JobsCase, async: false

  alias Dawarich.Ingest.Intake
  alias Dawarich.Jobs.Ownership

  alias Dawarich.Tracks.{
    BackfillCommands,
    BackfillRanges,
    BackfillWorker,
    RealtimeWorker,
    ThrottledBackfillWorker
  }

  @now ~U[2026-10-04 12:00:00.000000Z]
  @epoch DateTime.to_unix(@now)

  setup do
    start_oban(__MODULE__)
    start_supervised!(hd(Dawarich.Redis.child_specs()))
    old = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    for key <-
          ~w(command:tracks.backfill command:tracks.generate_range command:tracks.throttled_backfill command:tracks.generate_realtime),
        do: Ownership.put!(ScratchRepo, key, :sidekiq, pinned: true)

    rows(
      "INSERT INTO users(id,email,status,settings,created_at,updated_at) VALUES(1,'rxtracks@example.test',1,$1,now(),now())",
      [%{"timezone" => "UTC"}]
    )

    on_exit(fn ->
      if old, do: System.put_env("DAWARICH_RAILS", old), else: System.delete_env("DAWARICH_RAILS")
      Dawarich.Redis.command(["DEL", "track_throttled_backfill:user:1"])
    end)

    :ok
  end

  @tag a12f3b_case: "R04k01"
  test "tracks.backfill native producer reaches its source terminal effect" do
    input = Intake.prepare([%{lonlat: "POINT(1 1)", timestamp: @epoch - 100_000}], 1)
    for _ <- 1..2, do: Intake.write(input, 1, repo: ScratchRepo, now: @now)

    assert [[payload, due]] =
             rows(
               "SELECT payload,scheduled_at FROM job_outbox WHERE command_type='tracks.backfill'"
             )

    assert due == DateTime.add(@now, 60)
    assert payload["time_zone"] == "Etc/UTC"

    assert rows("SELECT cycle_id::text FROM phoenix.track_backfill_ranges") == [
             [payload["cycle_id"]]
           ]

    assert reverse("tracks.backfill") == []

    assert Dawarich.Jobs.Dispatch.run(
             repo: ScratchRepo,
             oban: __MODULE__,
             now: DateTime.add(@now, 60)
           ) == %{dispatched: 1}

    assert [[args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [inspect(BackfillWorker)])

    assert args["event_id"] == payload["cycle_id"]
    assert args["cycle_id"] == payload["cycle_id"]
    System.delete_env("DAWARICH_RAILS")
    Intake.write(input, 1, repo: ScratchRepo, now: @now)
    assert [[reverse]] = reverse("tracks.backfill")
    assert reverse["timestamps"] == [@epoch - 100_000, @epoch - 100_000]
    rows("DELETE FROM phoenix.rails_commands")
    Ownership.put!(ScratchRepo, "command:tracks.backfill", :oban)

    ctx = %{
      repo: ScratchRepo,
      id: 1,
      settings: %{"timezone" => "UTC"},
      event: Ecto.UUID.generate(),
      now: @now
    }

    Dawarich.Imports.Teslamate.Effects.finalize(ctx, %{
      range: {@epoch - 100_000, @epoch - 90_000},
      months: []
    })

    assert reverse("tracks.backfill") == []

    assert rows("SELECT latest_timestamp FROM phoenix.track_backfill_ranges") == [
             [@epoch - 90_000]
           ]
  end

  @tag a12f3b_case: "R04k02"
  test "tracks_generate_range native producer reaches its source terminal effect" do
    {:ok, {:inserted, range}} =
      BackfillRanges.put(ScratchRepo, 1, [@epoch - 100_000, @epoch - 90_000], "UTC", @now, fn _ ->
        :ok
      end)

    args = %{"user_id" => 1, "cycle_id" => range.cycle_id}
    for _ <- 1..2, do: assert(BackfillWorker.run(ScratchRepo, __MODULE__, args, now: @now) == :ok)

    assert [[payload]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1", [
               inspect(Dawarich.Tracks.RangeWorker)
             ])

    assert payload["event_id"] == range.cycle_id
    assert payload["untracked_only"] == true
    assert payload["time_zone"] == "Etc/UTC"
    assert payload["start_at"] == "2026-10-03T00:00:00.000000Z"
    assert reverse("tracks_generate_range") == []
    System.delete_env("DAWARICH_RAILS")

    {:ok, {:inserted, next}} =
      BackfillRanges.put(ScratchRepo, 1, [@epoch - 100_000], "UTC", @now, fn _ -> :ok end)

    assert BackfillWorker.run(
             ScratchRepo,
             __MODULE__,
             %{"user_id" => 1, "cycle_id" => next.cycle_id},
             now: @now
           ) == :ok

    assert [[%{"user_id" => 1}]] = reverse("tracks_generate_range")
  end

  @tag a12f3b_case: "R04k03"
  test "tracks_throttled_backfill native producer reaches its source terminal effect" do
    Dawarich.Redis.command(["SET", "track_throttled_backfill:user:1", "1", "EX", "36000"])

    rows("INSERT INTO points(user_id,timestamp,created_at,updated_at) VALUES(1,$1,now(),now())", [
      @epoch - 100_000
    ])

    assert {:inserted, walk} =
             BackfillCommands.schedule(ScratchRepo, 1, now: @now, time_zone: "UTC")

    assert BackfillCommands.schedule(ScratchRepo, 1, now: @now) == :occupied
    assert reverse("tracks_throttled_backfill") == []

    args = %{
      "user_id" => 1,
      "walk_id" => walk.walk_id,
      "cursor_timestamp" => nil,
      "time_zone" => "UTC"
    }

    for _ <- 1..2,
        do: assert(ThrottledBackfillWorker.run(ScratchRepo, __MODULE__, args, now: @now) == :ok)

    assert [[next, due]] =
             rows("SELECT args,scheduled_at FROM oban.oban_jobs WHERE worker=$1", [
               inspect(ThrottledBackfillWorker)
             ])

    assert next["walk_id"] == walk.walk_id
    assert next["cursor_timestamp"] == @epoch - 100_000 - 2_592_000
    assert DateTime.from_naive!(due, "Etc/UTC") == DateTime.add(@now, 60)
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[1]]
    assert reverse("tracks_generate_range") == []
    System.delete_env("DAWARICH_RAILS")
    assert BackfillCommands.schedule(ScratchRepo, 1, now: @now) == :ok
    assert [[%{"user_id" => 1}]] = reverse("tracks_throttled_backfill")
  end

  @tag a12f3b_case: "R04k04"
  test "tracks_realtime_retrigger native producer reaches its source terminal effect" do
    hold_lease!(ScratchRepo, Dawarich.Tracks.PerUserLock.key(1), "foreign")

    for _ <- 1..2 do
      assert RealtimeWorker.run(ScratchRepo, __MODULE__, %{"user_id" => 1},
               now: @epoch,
               lock: [timeout_ms: 0]
             ) == :ok
    end

    assert [[%{"user_id" => 1}, due]] =
             rows("SELECT args,scheduled_at FROM oban.oban_jobs WHERE worker=$1", [
               inspect(RealtimeWorker)
             ])

    assert DateTime.from_naive!(due, "Etc/UTC") == DateTime.add(@now, 45)
    assert reverse("tracks_realtime_retrigger") == []
    System.delete_env("DAWARICH_RAILS")

    assert RealtimeWorker.run(ScratchRepo, __MODULE__, %{"user_id" => 1},
             now: @epoch,
             lock: [timeout_ms: 0]
           ) == :ok

    assert [[%{"user_id" => 1}]] = reverse("tracks_realtime_retrigger")
  end

  defp reverse(kind), do: rows("SELECT payload FROM phoenix.rails_commands WHERE kind=$1", [kind])
end
