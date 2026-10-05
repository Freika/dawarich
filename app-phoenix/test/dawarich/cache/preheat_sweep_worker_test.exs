defmodule Dawarich.Cache.PreheatSweepWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatSweepWorker, as: Worker
  alias Dawarich.Jobs.Ownership

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
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    Ownership.put!(ScratchRepo, key, :sidekiq)
    send(after_pid, :delegate)
    assert Task.await(after_commit) == :ok
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
    assert Worker.run(ScratchRepo) == {:cancel, :not_owner}

    kase = Dawarich.DigestFixtures.case!("berlin_yearly")
    Dawarich.DigestFixtures.load!(ScratchRepo, kase)
    Ownership.put!(ScratchRepo, "command:cache.preheat_user", :sidekiq)

    args = %{
      "user_id" => 14101,
      "time_zone" => "Europe/Berlin",
      "source_job_id" => Ecto.UUID.generate()
    }

    assert Dawarich.Cache.PreheatUserWorker.perform(%Oban.Job{args: args}) == :ok
    assert length(Dawarich.DigestFixtures.digests(ScratchRepo, 14101)) == 2
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
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

    assert [["cache.preheat_sweep", payload]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert payload == %{
             "time_zone" => "Europe/Berlin",
             "source_job_id" => source,
             "run_at" => now + 3600
           }

    assert [[0]] = rows("SELECT count(*) FROM oban.oban_jobs")
    assert [[0]] = rows("SELECT count(*) FROM public.job_outbox")
    assert Worker.run(ScratchRepo, time_zone: "Etc/UTC", clock: now) == :ok

    [[uuid]] =
      rows(
        "SELECT payload->>'source_job_id' FROM phoenix.rails_commands ORDER BY id DESC LIMIT 1"
      )

    assert {:ok, _} = Ecto.UUID.cast(uuid)
    refute uuid == source
    changeset = Worker.new(%{}) |> Ecto.Changeset.apply_changes()
    assert changeset.queue == "projections"
    assert changeset.max_attempts == 3
    assert changeset.unique == nil
  end
end
