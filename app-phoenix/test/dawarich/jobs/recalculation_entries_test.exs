defmodule Dawarich.Jobs.RecalculationEntriesTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.{Dispatch, Registry}
  alias Dawarich.Users.RecalculateWorker

  @workers %{
    "stats.full_recalculation" => Dawarich.Stats.FullRecalculationWorker,
    "users.recalculate_data" => RecalculateWorker,
    "points.anomaly_backfill" => Dawarich.Points.AnomalyBackfillWorker,
    "release.anomalies" => Dawarich.ReleaseOperations.Anomalies,
    "release.anomalies_user" => Dawarich.ReleaseOperations.AnomaliesUser,
    "release.per_tracker" => Dawarich.ReleaseOperations.PerTracker
  }

  test "registers six unclaimable entries and decodes only the recorded anomaly/tracker forms" do
    for {type, worker} <- @workers do
      entry = Enum.find(Registry.entries(), &(&1.key == "command:" <> type))
      assert %{kind: :command, claimable: false, worker: ^worker} = entry
      refute entry in Registry.claimable()
      assert Registry.command(type) == {:ok, worker}
    end

    for {class, worker} <- [
          {"DataMigrations::RecalculateAnomaliesJob", Dawarich.ReleaseOperations.Anomalies},
          {"DataMigrations::RecalculatePerTrackerTracksJob",
           Dawarich.ReleaseOperations.PerTracker}
        ] do
      assert {:ok, ^worker, args} = Dawarich.ReleaseJobs.decode(class, [])
      source = args["cursor"]["request"]["source_job_id"]
      assert {:ok, ^source} = Ecto.UUID.cast(source)

      assert worker.args_from_command(1, args["cursor"]["request"]) ==
               {:ok, Map.delete(args, "operation_id")}

      assert Dawarich.ReleaseJobs.decode(class, [nil]) == {:error, :invalid_arguments}
    end
  end

  test "keeps migrator recording inert while its returned workers are executable" do
    refute Enum.any?(Dawarich.Jobs.RecalculationEntries.entries(), & &1.claimable)
    module = Dawarich.ReleaseMigrations.V1_11_0
    targets = ~w(20260730160000 20260802120000)
    versions = Enum.map(module.steps(), &elem(&1, 0))
    before = rows("SELECT version FROM schema_migrations WHERE version=ANY($1)", [versions])
    recorded = rows("SELECT id FROM phoenix.release_migration_jobs") |> List.flatten()

    try do
      for version <- versions -- targets do
        rows("INSERT INTO schema_migrations(version) VALUES($1) ON CONFLICT DO NOTHING", [version])
      end

      rows("DELETE FROM schema_migrations WHERE version=ANY($1)", [targets])

      assert {:ok, %{applied: ^targets}} =
               Dawarich.ReleaseMigrator.apply_release_for_proof(ScratchRepo, module)

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
      assert rows("SELECT count(*) FROM phoenix.release_operations") == [[0]]

      source = Dawarich.RecalculationFixtures.case!("tracker_stagger")
      Dawarich.RecalculationFixtures.load!(ScratchRepo, source)
      start_oban(:recorded_recalculations)

      for [class, arguments] <-
            rows(
              "SELECT job_class,arguments FROM phoenix.release_migration_jobs WHERE NOT(id=ANY($1))",
              [recorded]
            ) do
        assert {:ok, worker, args} = Dawarich.ReleaseJobs.decode(class, arguments)

        assert :ok =
                 Dawarich.ReleaseOperations.run(
                   ScratchRepo,
                   :recorded_recalculations,
                   worker,
                   %Oban.Job{args: args}
                 )

        assert :ok =
                 Dawarich.ReleaseOperations.run(
                   ScratchRepo,
                   :recorded_recalculations,
                   worker,
                   %Oban.Job{args: args}
                 )
      end

      assert rows("SELECT count(*) FROM phoenix.release_operations WHERE status='completed'") == [
               [2]
             ]

      assert rows("SELECT count(*) FROM oban.oban_jobs") == [[2]]
    after
      rows("DELETE FROM phoenix.release_migration_jobs WHERE NOT(id=ANY($1))", [recorded])
      rows("DELETE FROM schema_migrations WHERE version=ANY($1)", [versions])

      for [version] <- before,
          do: rows("INSERT INTO schema_migrations(version) VALUES($1)", [version])
    end
  end

  test "disabled user rebuild entry dispatches complete payloads to the real Oban worker" do
    oban = :recalculation_entries
    start_oban(oban)
    entry = Enum.find(Registry.entries(), &(&1.key == "command:users.recalculate_data"))
    assert %{kind: :command, claimable: false, worker: RecalculateWorker} = entry
    refute entry in Registry.claimable()
    assert Registry.command("users.recalculate_data") == {:ok, RecalculateWorker}

    payload = %{
      "user_id" => 170_101,
      "year" => 2025,
      "notify" => false,
      "job_queue" => "low_priority",
      "source_job_id" => Ecto.UUID.generate(),
      "ambient_zone" => "Asia/Tokyo"
    }

    assert RecalculateWorker.args_from_command(1, payload) == {:ok, payload}
    event = outbox!(command_type: "users.recalculate_data", payload: payload)
    assert Dispatch.run(repo: ScratchRepo, oban: oban) == %{dispatched: 1}

    assert [[args, "Dawarich.Users.RecalculateWorker", "projections"]] =
             rows("SELECT args,worker,queue FROM oban.oban_jobs")

    assert args == Map.put(payload, "event_id", event)
    assert rows("SELECT count(*) FROM phoenix.job_owners") == [[0]]

    assert rows("SELECT state FROM public.job_outbox WHERE event_id=$1", [Ecto.UUID.dump!(event)]) ==
             [["dispatched"]]
  end
end
