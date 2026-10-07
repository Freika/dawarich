defmodule Dawarich.Imports.LegacyZipChildTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.ProcessWorker
  alias Dawarich.Jobs.{Ownership, Processed, Registry}

  setup do: F.setup()

  for mode <- ["on", "off"] do
    test "legacy ZIP child retains terminal disposition before parent removal in #{mode}", c do
      System.put_env("DAWARICH_RAILS", unquote(mode))
      for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)
      rows("UPDATE imports SET source=NULL WHERE id=$1", [c.import.id])

      rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
        c.job.id
      ])

      c = %{c | job: %{c.job | worker: "Dawarich.Imports.ProcessWorker"}}

      legacy =
        File.read!(
          Path.expand(
            "../../fixtures/imports/formats/whole_create/zip_unsafe_skip.input.zip",
            __DIR__
          )
        )

      {:ok, {_, bytes}} =
        :zip.create(
          ~c"outer.zip",
          [
            {~c"legacy.kmz", legacy},
            {~c"points.csv", "latitude,longitude,timestamp\n52.5,13.4,1768521600\n"}
          ],
          [:memory]
        )

      F.blob(c, "outer.zip", bytes, "file")
      start_oban(__MODULE__)
      assert {:snooze, 5} = ProcessWorker.perform(c.job)
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])

      if unquote(mode) == "on",
        do:
          assert(
            %{dispatched: 2} =
              Dawarich.Jobs.Dispatch.run(
                now: Dawarich.JobsCase.db_now(ScratchRepo),
                repo: ScratchRepo,
                oban: __MODULE__
              )
          )

      assert [[child]] =
               rows(
                 "SELECT child_id FROM phoenix.import_archive_children WHERE parent_id=$1 AND entry_name='legacy.kmz'",
                 [c.import.id]
               )

      for [id, args, worker] <-
            rows(
              "UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id<>$1 AND worker='Dawarich.Imports.ProcessWorker' RETURNING id,args,worker",
              [c.job.id]
            ) do
        owner = if unquote(mode) == "on" and args["import_id"] == child, do: :sidekiq, else: :oban
        Ownership.put!(ScratchRepo, "command:imports.process_normal", owner, pinned: true)

        assert :ok =
                 ProcessWorker.perform(%Oban.Job{id: id, args: args, worker: worker, attempt: 1})
      end

      Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban, pinned: true)

      if unquote(mode) == "on" do
        assert [[false, "pending"]] ==
                 rows(
                   "SELECT native_fallback,state FROM phoenix.import_handoffs WHERE import_id=$1",
                   [child]
                 )

        assert {:snooze, 5} = ProcessWorker.perform(c.job)

        rows(
          "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
          [child]
        )

        rows("DELETE FROM imports WHERE id=$1", [child])
        assert {:snooze, 5} = ProcessWorker.perform(c.job)
        rows("UPDATE phoenix.import_handoffs SET state='completed' WHERE import_id=$1", [child])
      else
        assert [[3]] == rows("SELECT status FROM imports WHERE id=$1", [child])

        assert [[1]] ==
                 rows("SELECT count(*) FROM notifications WHERE user_id=$1 AND kind=2", [
                   c.import.user_id
                 ])

        assert [] == rows("SELECT kind FROM phoenix.rails_commands")
      end

      assert :ok = ProcessWorker.perform(c.job)
      assert [] == rows("SELECT id FROM imports WHERE id=$1", [c.import.id])
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [[1]] == rows("SELECT count(*) FROM points WHERE user_id=$1", [c.import.user_id])
      assert :ok = ProcessWorker.perform(c.job)
    end
  end
end
