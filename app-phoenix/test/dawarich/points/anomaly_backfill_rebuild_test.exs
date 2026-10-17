defmodule Dawarich.Points.AnomalyBackfillRebuildTest do
  use Dawarich.JobsCase

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Points.AnomalyBackfillWorker, as: Worker
  alias Dawarich.Jobs.{Dispatch, Ownership, Processed}
  alias Dawarich.State

  setup do
    pool =
      start_supervised!({ScratchRepo, [name: nil, pool_size: 2, parameters: [timezone: "UTC"]]},
        id: :utc_rebuild
      )

    ScratchRepo.put_dynamic_repo(pool)
    on_exit(fn -> ScratchRepo.put_dynamic_repo(ScratchRepo) end)
    start_oban(:anomaly_rebuild)
    :ok
  end

  test "a standalone busy request completes without scheduling a later reset" do
    source = Fixtures.case!("backfill_busy")
    Fixtures.load!(ScratchRepo, source)
    args = args(source, "inline")
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:dawarich, :jobs_repo, previous),
        else: Application.delete_env(:dawarich, :jobs_repo)
    end)

    hold_lease!(ScratchRepo, "anomaly_backfill:170101", "other")
    job = Oban.insert!(:anomaly_rebuild, Worker.new(args))
    drained = Oban.drain_queue(:anomaly_rebuild, queue: :maintenance)
    assert drained.success == 1
    assert drained.snoozed == 0
    assert rows("SELECT state FROM oban.oban_jobs WHERE id=$1", [job.id]) == [["completed"]]
    rows("DELETE FROM phoenix.leases WHERE holder='other'")

    assert Oban.drain_queue(:anomaly_rebuild, queue: :maintenance, with_scheduled: true).success ==
             0

    assert rows("SELECT anomaly FROM points WHERE id=170201") == [[true]]

    for table <- ~w(stats digests notifications phoenix.track_generations phoenix.rails_commands),
        do: assert(rows("SELECT count(*) FROM " <> table) == [[0]])
  end

  test "distinguishes busy interrupted and completed inline rebuild outcomes" do
    source = Fixtures.case!("backfill_reset")
    Fixtures.load!(ScratchRepo, source)
    args = args(source, "inline")
    hold_lease!(ScratchRepo, "anomaly_backfill:170101", "other")
    assert Worker.run(ScratchRepo, :anomaly_rebuild, args, lease: [timeout_ms: 0]) == {:ok, false}
    assert rows("SELECT anomaly FROM points WHERE id=170201") == [[true]]
    assert not Processed.done?(ScratchRepo, args["event_id"])
    end_foreign_lease!("anomaly_backfill:170101")
    rows("DELETE FROM phoenix.leases WHERE holder='other'")

    assert Worker.run(ScratchRepo, :anomaly_rebuild, args, after_month: fn _ -> :interrupted end) ==
             {:ok, nil}

    assert not Processed.done?(ScratchRepo, args["event_id"])
    assert State.cursor(ScratchRepo, key(args)) != nil
    assert rows("SELECT count(*) FROM stats") == [[0]]

    assert_raise RuntimeError, "before_parent", fn ->
      Worker.run(
        ScratchRepo,
        :anomaly_rebuild,
        args,
        options(phase: fn :tracks, _, _ -> raise "before_parent" end)
      )
    end

    assert rows("SELECT count(*) FROM stats") != [[0]]
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[0]]
    assert not Processed.done?(ScratchRepo, args["event_id"])
    assert State.cursor(ScratchRepo, key(args)) != nil
    assert rows("SELECT kind FROM notifications") == [[2]]
    rows("DELETE FROM notifications")
    hold_lease!(ScratchRepo, "tracks:per_user_lock:170101", "other")

    assert Worker.run(
             ScratchRepo,
             :anomaly_rebuild,
             args,
             options(range_opts: [lock: [timeout_ms: 0]])
           ) == {:error, :lock_busy}

    assert not Processed.done?(ScratchRepo, args["event_id"])
    assert State.cursor(ScratchRepo, key(args)) != nil
    assert rows("SELECT count(*) FROM notifications") == [[0]]
    rows("DELETE FROM phoenix.leases WHERE holder='other'")
    assert Worker.run(ScratchRepo, :anomaly_rebuild, args, options()) == {:ok, true}
    assert Processed.done?(ScratchRepo, args["event_id"])
    assert State.cursor(ScratchRepo, key(args)) == nil
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[1]]
    assert rows("SELECT count(*) FROM digests") == [[2]]
    assert rows("SELECT kind FROM notifications") == [[0]]
    count = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert Worker.run(ScratchRepo, :anomaly_rebuild, args, options()) == {:ok, true}
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == count
    missing = Map.merge(args, %{"user_id" => -1, "event_id" => Ecto.UUID.generate()})

    assert_raise Dawarich.Digests.Context.UserNotFound, fn ->
      Worker.run(ScratchRepo, :anomaly_rebuild, missing)
    end

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, source)
    assert Worker.run(ScratchRepo, :anomaly_rebuild, Map.put(args, "reset", false)) == {:ok, true}
    assert rows("SELECT count(*) FROM stats") == [[0]]
    assert rows("SELECT count(*) FROM digests") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.track_generations") == [[0]]
    assert rows("SELECT count(*) FROM phoenix.rails_commands") == [[0]]
  end

  test "async reset durably routes user rebuild and oldest achievement request once" do
    source = Fixtures.case!("backfill_async")

    for owner <- [:sidekiq, :oban] do
      reset!(ScratchRepo)
      Fixtures.load!(ScratchRepo, source)
      args = args(source, "async")
      Ownership.put!(ScratchRepo, "command:users.recalculate_data", owner)
      Ownership.put!(ScratchRepo, "command:achievements.check", owner)
      assert Worker.run(ScratchRepo, :anomaly_rebuild, args) == {:ok, true}
      assert Worker.run(ScratchRepo, :anomaly_rebuild, args) == {:ok, true}

      payload = %{
        "user_id" => 170_101,
        "year" => nil,
        "notify" => true,
        "job_queue" => nil,
        "source_job_id" => Worker.rebuild_id(args),
        "ambient_zone" => "Europe/Berlin"
      }

      achievement = %{"user_id" => 170_101, "notify" => true, "oldest_timestamp" => 1_735_687_800}

      if owner == :sidekiq do
        assert [[reverse]] =
                 rows(
                   "SELECT payload FROM phoenix.rails_commands WHERE kind='users.recalculate_data'"
                 )

        assert Map.delete(reverse, "run_at") == payload

        assert [[reverse]] =
                 rows(
                   "SELECT payload FROM phoenix.rails_commands WHERE kind='achievements.check'"
                 )

        assert Map.delete(reverse, "run_at") == achievement
        assert rows("SELECT count(*) FROM job_outbox") == [[0]]
      else
        assert rows("SELECT payload FROM job_outbox WHERE command_type='users.recalculate_data'") ==
                 [[payload]]

        assert rows("SELECT payload FROM job_outbox WHERE command_type='achievements.check'") == [
                 [achievement]
               ]

        [[now]] = rows("SELECT clock_timestamp()")

        assert Dispatch.run(repo: ScratchRepo, oban: :anomaly_rebuild, now: now) == %{
                 dispatched: 2
               }

        assert rows("SELECT worker FROM oban.oban_jobs ORDER BY worker") == [
                 ["Dawarich.Achievements.CheckWorker"],
                 ["Dawarich.Users.RecalculateWorker"]
               ]
      end

      assert rows("SELECT count(*) FROM stats") == [[0]]
      assert rows("SELECT count(*) FROM notifications") == [[0]]
    end
  end

  defp args(source, rebuild),
    do: %{
      "user_id" => 170_101,
      "reset" => true,
      "notify" => true,
      "rebuild" => rebuild,
      "source_job_id" => source["job"]["job_id"],
      "event_id" => source["job"]["job_id"],
      "ambient_zone" => "Europe/Berlin",
      "progress" => %{}
    }

  defp key(args), do: "anomaly_backfill:progress:" <> args["event_id"]

  defp options(extra \\ []),
    do: Keyword.merge([now: ~U[2026-10-03 12:00:00Z], env: %{"SELF_HOSTED" => "false"}], extra)
end
