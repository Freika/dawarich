defmodule Dawarich.A12f3bR10Test do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.Postprocessing.Commands
  setup do: F.setup()

  @tag a12f3b_case: "R10k01"
  test "imports.progress native producer reaches its source terminal effect", c do
    Dawarich.Imports.Events.subscribe(c.import.user_id)
    state = %{at: nil, index: 0}
    assert %{index: 100} = Dawarich.Imports.GpxProgress.record(c.import, 100, state, c.context)
    assert_receive :imports_changed
    assert [[100]] == rows("SELECT processed FROM imports WHERE id=$1", [c.import.id])
    assert [] == F.reverse()
    F.blob(c, "lifecycle.gpx", "<gpx><trk/></gpx>", "file")

    context =
      Map.merge(c.context, %{
        services: %{"local" => %{service: "local", root: c.root}},
        temp_dir: c.root,
        self_hosted?: true
      })

    assert {:ok, :ok} ==
             Dawarich.Imports.Lease.with_import(
               ScratchRepo,
               c.job,
               c.import,
               &Dawarich.Imports.GpxLifecycle.call(&1, context)
             )

    assert [[2]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
    assert [] == F.reverse()
    System.delete_env("DAWARICH_RAILS")
    Dawarich.Imports.GpxProgress.record(c.import, 200, state, c.context)
    assert [["imports.progress"]] == F.reverse()
  end

  @tag a12f3b_case: "R10k03"
  test "imports.destroy_requested native producer reaches its source terminal effect", c do
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.destroy", :sidekiq, pinned: true)

    assert {:ok, :queued} ==
             Dawarich.Imports.Destroy.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               c.context
             )

    assert [] == F.reverse()
    start_oban(__MODULE__)
    assert %{dispatched: 1} == Dawarich.Jobs.Dispatch.run(repo: ScratchRepo, oban: __MODULE__)
    foreign_lease!("import:#{c.import.id}")
    assert %{snoozed: 1} = Oban.drain_queue(__MODULE__, queue: :imports)
    assert [[4]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
    end_foreign_lease!("import:#{c.import.id}")

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(__MODULE__, queue: :imports, with_scheduled: true)

    assert [] == rows("SELECT id FROM imports WHERE id=$1", [c.import.id])
    assert [] == F.reverse()
  end

  @tag a12f3b_case: "R10k04"
  test "imports.destroy_status native producer reaches its source terminal effect", c do
    System.delete_env("DAWARICH_RAILS")
    c = F.destroy(c)
    Dawarich.Imports.Events.subscribe(c.import.user_id)

    assert {:ok, :ok} =
             F.with_destroy(c, fn lease ->
               Dawarich.Imports.DestroyEffects.status!(lease)
               assert_receive :imports_changed
               assert [[4]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
               assert [] == F.reverse()
               rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])

               assert_raise Dawarich.Imports.LeaseLost, fn ->
                 Dawarich.Imports.DestroyEffects.status!(lease)
               end

               :ok
             end)
  end

  @tag a12f3b_case: "R10k02"
  test "imports.postprocessing_step native producer reaches its source terminal effect", c do
    for _ <- 1..2 do
      {:ok, :ok} =
        ScratchRepo.transaction(fn ->
          Commands.reverse!(ScratchRepo, c.import, c.context, "schedule_stats", %{
            "months" => [[2025, 12], [2026, 1]],
            "oldest_timestamp" => 100
          })

          Commands.reverse!(ScratchRepo, c.import, c.context, "schedule_visit_suggesting", %{
            "start_at" => "2025-12-31T23:00:00Z",
            "end_at" => "2026-01-01T02:00:00Z"
          })

          Commands.reverse!(ScratchRepo, c.import, c.context, "extract")
          :ok
        end)
    end

    assert [] == F.reverse()
    workers = F.workers()
    assert Enum.count(workers, &(&1 == "Dawarich.Stats.CalculateMonthWorker")) == 2
    assert Enum.count(workers, &(&1 == "Dawarich.Achievements.CheckWorker")) == 1
    assert Enum.count(workers, &(&1 == "Dawarich.Visits.SuggestWorker")) == 1
    assert Enum.count(workers, &(&1 == "Dawarich.EnhancedImport.NormalWorker")) == 1

    assert [
             [
               %{
                 "user_id" => user,
                 "start_at" => 1_767_222_000,
                 "end_at" => 1_767_232_800,
                 "cursor" => 1_767_222_000,
                 "stepping" => "calendar",
                 "time_zone" => "Europe/Berlin",
                 "plan_restricted" => false,
                 "event_id" => _
               }
             ]
           ] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Visits.SuggestWorker'")

    assert user == c.import.user_id
    System.delete_env("DAWARICH_RAILS")

    assert {:ok, _} =
             ScratchRepo.transaction(fn ->
               Commands.reverse!(ScratchRepo, c.import, c.context, "schedule_stats", %{
                 "months" => [],
                 "oldest_timestamp" => nil
               })
             end)

    assert [["imports.postprocessing_step"]] == F.reverse()
  end
end
