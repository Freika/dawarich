defmodule Dawarich.Cache.ScheduleTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.Schedule
  alias Dawarich.Jobs.Ownership

  test "standalone preheating schedules the existing native consumer while respecting pinned Rails ownership" do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    source = Ecto.UUID.generate()
    now = 1_791_028_800
    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :oban)

    assert Schedule.preheat_user(ScratchRepo, 14101,
             source_job_id: source,
             time_zone: "Etc/UTC",
             clock: now,
             schedule_in: 3600
           ) == :ok

    assert [[args, at]] =
             rows(
               "SELECT args,scheduled_at FROM oban.oban_jobs WHERE worker='Dawarich.Cache.PreheatUserWorker'"
             )

    assert args["source_job_id"] == source
    assert args["event_id"] == source
    assert args["time_zone"] == "Etc/UTC"

    assert NaiveDateTime.compare(at, DateTime.from_unix!(now + 3600) |> DateTime.to_naive()) ==
             :eq

    assert {:ok, _} =
             Dawarich.Cache.PreheatUserWorker.args_from_command(1, Map.delete(args, "event_id"))

    assert [] == rows("SELECT kind FROM phoenix.rails_commands")
    assert :ok = Dawarich.Cache.PreheatUserWorker.run(ScratchRepo, args)
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, source)
    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :sidekiq, pinned: true)
    assert Schedule.preheat_user(ScratchRepo, 14101, clock: now) == :ok
    assert [["cache.preheat_user"]] == rows("SELECT kind FROM phoenix.rails_commands")
    assert [[1]] == rows("SELECT count(*) FROM oban.oban_jobs")
  end

  test "both owners retain Rails warming before current-owner durable dispatch with stable identity zone and time" do
    source = Ecto.UUID.generate()
    now = 1_791_028_800
    start_oban(CacheSchedule)

    for owner <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      Ownership.put!(ScratchRepo, "command:cache.preheat_user", owner)

      assert Schedule.preheat_user(ScratchRepo, 14101,
               source_job_id: source,
               oban: CacheSchedule,
               time_zone: "Europe/Berlin",
               clock: now,
               schedule_in: 3600
             ) == :ok

      assert [["cache.preheat_user", payload]] =
               rows("SELECT kind,payload FROM phoenix.rails_commands")

      assert payload == %{
               "user_id" => 14101,
               "time_zone" => "Europe/Berlin",
               "source_job_id" => source,
               "run_at" => now + 3600
             }

      assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
      assert [[0]] = rows("SELECT count(*) FROM public.job_outbox")
      assert Schedule.preheat_user(ScratchRepo, 14101, time_zone: "Etc/UTC", clock: now) == :ok

      [[generated]] =
        rows(
          "SELECT payload->>'source_job_id' FROM phoenix.rails_commands ORDER BY id DESC LIMIT 1"
        )

      assert {:ok, _} = Ecto.UUID.cast(generated)
      refute generated == source

      rows(
        "ALTER TABLE phoenix.rails_commands ADD CONSTRAINT a12d1b4_reject_user CHECK(kind<>'cache.preheat_user') NOT VALID"
      )

      assert_raise Postgrex.Error, fn -> Schedule.preheat_user(ScratchRepo, 14101, clock: now) end
      assert [[2]] = rows("SELECT count(*) FROM phoenix.rails_commands")
      rows("ALTER TABLE phoenix.rails_commands DROP CONSTRAINT a12d1b4_reject_user")
    end
  after
    rows("ALTER TABLE phoenix.rails_commands DROP CONSTRAINT IF EXISTS a12d1b4_reject_user")
  end
end
