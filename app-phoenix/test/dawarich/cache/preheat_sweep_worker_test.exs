defmodule Dawarich.Cache.PreheatSweepWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Cache.PreheatSweepWorker, as: Worker
  alias Dawarich.Jobs.Ownership

  test "owned native cron delegates one source warming sweep with carried zone and due time" do
    Ownership.put!(ScratchRepo, "cron:cache_preheating_job", :oban)
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
