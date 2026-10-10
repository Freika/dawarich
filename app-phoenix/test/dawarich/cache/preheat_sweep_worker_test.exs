defmodule Dawarich.Cache.PreheatSweepWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatSweepWorker, as: Worker
  alias Dawarich.Jobs.Ownership

  setup do
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)
    {:ok, _} = Dawarich.Redis.cache_command(["FLUSHDB"])
    Dawarich.DigestFixtures.load!(ScratchRepo, Dawarich.DigestFixtures.case!("berlin_yearly"))
    rows("UPDATE users SET deleted_at=now() WHERE id<>14101")
    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :oban)
    :ok
  end

  test "release cancels an undelegated sweep while committed warming requests and accepted user jobs remain drainable" do
    key = "cron:cache_preheating_job"
    Ownership.put!(ScratchRepo, key, :oban)
    parent = self()

    barrier = fn ->
      send(parent, {:ready, self()})
      receive do: (:delegate -> :ok)
    end

    before = Task.async(fn -> Worker.run(ScratchRepo, before_delegate: barrier) end)
    assert_receive {:ready, before_pid}, 5000
    Ownership.put!(ScratchRepo, key, :sidekiq)
    send(before_pid, :delegate)
    assert Task.await(before) == {:cancel, :not_owner}
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")

    Ownership.put!(ScratchRepo, key, :oban)
    after_commit = Task.async(fn -> Worker.run(ScratchRepo, after_delegate: barrier) end)
    assert_receive {:ready, after_pid}, 5000
    assert [[1]] = rows("SELECT count(*) FROM oban.oban_jobs")
    Ownership.put!(ScratchRepo, key, :sidekiq)
    send(after_pid, :delegate)
    assert Task.await(after_commit) == :ok
    assert [[1]] = rows("SELECT count(*) FROM oban.oban_jobs")
    assert Worker.run(ScratchRepo) == {:cancel, :not_owner}

    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :sidekiq)

    args = %{
      "user_id" => 14101,
      "time_zone" => "Europe/Berlin",
      "source_job_id" => Ecto.UUID.generate()
    }

    assert Dawarich.Cache.PreheatUserWorker.perform(%Oban.Job{args: args}) == :ok
    assert length(Dawarich.DigestFixtures.digests(ScratchRepo, 14101)) == 2
    assert [[1]] = rows("SELECT count(*) FROM oban.oban_jobs")
  end

  test "owned native cron delegates one source warming sweep with carried zone and due time" do
    source = Ecto.UUID.generate()
    now = 1_791_028_800
    start_oban(CacheSweep)

    opts = [
      source_job_id: source,
      time_zone: "Europe/Berlin",
      clock: now,
      schedule_in: 3600,
      oban: CacheSweep
    ]

    Ownership.put!(ScratchRepo, "cron:cache_preheating_job", :sidekiq)
    assert Worker.run(ScratchRepo, opts) == {:cancel, :not_owner}
    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")

    Ownership.put!(ScratchRepo, "cron:cache_preheating_job", :oban)
    assert Worker.run(ScratchRepo, opts) == :ok

    assert [[args, at]] = rows("SELECT args,scheduled_at FROM oban.oban_jobs")
    assert args["time_zone"] == "Europe/Berlin"
    expected = :crypto.hash(:md5, "#{source}/14101") |> Ecto.UUID.load!()
    assert args["source_job_id"] == expected
    assert args["event_id"] == expected

    assert NaiveDateTime.compare(at, DateTime.from_unix!(now + 3600) |> DateTime.to_naive()) ==
             :eq

    assert [[0]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert [[0]] = rows("SELECT count(*) FROM public.job_outbox")
    assert Worker.run(ScratchRepo, time_zone: "Etc/UTC", clock: now) == :ok
    assert [[2]] = rows("SELECT count(*) FROM oban.oban_jobs")
    changeset = Worker.new(%{}) |> Ecto.Changeset.apply_changes()
    assert changeset.queue == "projections"
    assert changeset.max_attempts == 3
    assert changeset.unique == nil
  end
end
