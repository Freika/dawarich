defmodule Dawarich.A12f3bG03Test do
  use Dawarich.JobsCase

  alias Dawarich.Geocoding.NightlyWorker
  alias Dawarich.Jobs.{Ownership, Registry}
  alias Dawarich.Tracks.DailyWorker

  defmodule RollbackRepo do
    def transaction(fun),
      do:
        Dawarich.ScratchRepo.transaction(fn ->
          fun.()
          Dawarich.ScratchRepo.rollback(:interrupted)
        end)

    def query!(sql, args, opts), do: Dawarich.ScratchRepo.query!(sql, args, opts)
    defdelegate all(query), to: Dawarich.ScratchRepo
    defdelegate one(query), to: Dawarich.ScratchRepo
    defdelegate update_all(query, opts), to: Dawarich.ScratchRepo
  end

  @oban __MODULE__.Oban
  @slot 1_759_050_000
  @now ~U[2025-09-28 09:05:00Z]

  setup do
    start_oban(@oban)
    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

    for name <- ~w(SELF_HOSTED RAILS_ENV DAWARICH_RAILS) do
      previous = System.get_env(name)

      on_exit(fn ->
        if previous, do: System.put_env(name, previous), else: System.delete_env(name)
      end)
    end

    System.put_env("SELF_HOSTED", "true")
    System.put_env("RAILS_ENV", "test")
    System.delete_env("DAWARICH_RAILS")
    :ok
  end

  @tag a12f3b_case: "G03a"
  test "composed source crons schedule native children and keep explicit commands distinct" do
    for name <-
          ~w(bulk_stats_calculating_job stats_toponyms_refresh_job daily_track_generation_job nightly_reverse_geocoding_job visit_suggesting_job achievements_bulk_check_job app_version_checking_job points_counter_correction_job watcher_job) do
      assert %{kind: :cron, catch_up: false} =
               Enum.find(Registry.entries(), &(&1.key == "cron:" <> name))
    end

    [[user]] =
      rows(
        "INSERT INTO users(email,status,created_at,updated_at) VALUES ('cron-native@example.test',1,now(),now()) RETURNING id"
      )

    [[point]] =
      rows(
        "INSERT INTO points(user_id,timestamp,created_at,updated_at) VALUES ($1,$2,now(),now()) RETURNING id",
        [user, @slot]
      )

    Ownership.put!(ScratchRepo, NightlyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:geocoding.reverse_point", :oban)

    assert NightlyWorker.run(ScratchRepo, @oban, @slot,
             env: %{"PHOTON_API_HOST" => "photon.example.invalid"}
           ) == :ok

    assert [["Dawarich.Geocoding.ReversePointWorker", "reverse_geocoding", args]] =
             rows("SELECT worker,queue,args FROM oban.oban_jobs")

    assert args["point_ids"] == [point]
    assert args["user_id"] == user
    assert args["force"] == false
    assert rows("SELECT kind FROM phoenix.rails_commands") == [["stats.caches_invalidated"]]

    System.put_env("DAWARICH_RAILS", "off")
    rows("DELETE FROM phoenix.rails_commands")

    rows(
      "INSERT INTO points(user_id,timestamp,created_at,updated_at) VALUES ($1,$2,now(),now())",
      [user, @slot + 60]
    )

    assert NightlyWorker.run(ScratchRepo, @oban, @slot + 60,
             env: %{"PHOTON_API_HOST" => "photon.example.invalid"}
           ) == :ok

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]

    assert {:ok, _} =
             Dawarich.Achievements.BulkCheckWorker.args_from_command(1, %{
               "notify" => false,
               "force" => true,
               "stale_only" => true
             })

    Ownership.put!(ScratchRepo, Dawarich.Users.PointsCounterCorrectionWorker.key(), :oban)

    assert Dawarich.Users.PointsCounterCorrectionWorker.run(RollbackRepo, 1000) ==
             {:error, :interrupted}
  end

  @tag a12f3b_case: "G03b"
  test "cron failure preserves source cursor and future child debt" do
    Ownership.put!(ScratchRepo, DailyWorker.key(), :oban)
    Ownership.put!(ScratchRepo, "command:tracks.generate_range", :oban)

    users =
      for n <- 1..3 do
        [[user]] =
          rows(
            "INSERT INTO users(email,status,points_count,settings,created_at,updated_at) VALUES ($1,1,1,$2,now(),now()) RETURNING id",
            ["cron-track-#{n}@example.test", %{"timezone" => "Europe/Berlin"}]
          )

        rows(
          "INSERT INTO points(user_id,timestamp,created_at,updated_at) VALUES ($1,$2,now(),now())",
          [user, @slot - 60]
        )

        user
      end

    [first, failing, last] = users
    hook = fn id -> if id == failing, do: ScratchRepo.query!("SELECT 1/0", [], log: false) end

    ExUnit.CaptureLog.capture_log(fn ->
      assert DailyWorker.run(ScratchRepo, @oban, @slot, now: @now, hook: hook) == :ok
    end)

    children = rows("SELECT args FROM oban.oban_jobs ORDER BY id")
    assert Enum.map(children, fn [args] -> args["user_id"] end) == [first, last]
    rows("UPDATE oban.oban_jobs SET state='scheduled',scheduled_at=now()+interval '1 hour'")
    assert DailyWorker.run(ScratchRepo, @oban, @slot, now: DateTime.add(@now, 60)) == :ok
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[3]]
    assert rows("SELECT args FROM oban.oban_jobs WHERE state='scheduled' ORDER BY id") == children

    assert Enum.map(
             rows("SELECT args FROM oban.oban_jobs ORDER BY (args->>'user_id')::bigint"),
             fn [args] -> args["event_id"] end
           ) == Enum.map(users, &DailyWorker.event_id(@slot, &1))

    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end
end
