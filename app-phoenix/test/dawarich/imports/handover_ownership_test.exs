defmodule Dawarich.Imports.HandoverOwnershipTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Jobs.{Ownership, Registry}
  setup do: F.setup()

  for {lane, module, worker, source, kind, selector} <- [
        {"imports.process_gpx", Dawarich.Imports.GpxHandover, "Dawarich.Imports.ProcessGpxWorker",
         4, "imports.resume", "R09gpxownership"},
        {"imports.process_normal", Dawarich.Imports.NormalHandover,
         "Dawarich.Imports.ProcessWorker", 10, "imports.normal_resume", "R09normalownership"}
      ] do
    @tag a12f3b_case: selector
    test "#{lane} legacy handover refuses native reverse and preserves Rails-owned resume", c do
      lane = unquote(lane)
      module = unquote(module)
      kind = unquote(kind)
      rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, unquote(source)])
      rows("UPDATE oban.oban_jobs SET worker=$2 WHERE id=$1", [c.job.id, unquote(worker)])

      for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)

      for mode <- ["on", "off"] do
        System.put_env("DAWARICH_RAILS", mode)
        result = module.resume(ScratchRepo, c.job, :legacy)
        assert [] == F.reverse()
        assert {:error, :unsupported_native_import} == result
        assert [] == rows("SELECT event_id FROM phoenix.import_handoffs")
        refute Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
        assert [[0]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      end

      System.put_env("DAWARICH_RAILS", "on")
      Ownership.put!(ScratchRepo, "command:" <> lane, :sidekiq, pinned: true)
      assert :ok == module.resume(ScratchRepo, c.job, :legacy)
      assert [[^kind, payload]] = rows("SELECT kind,payload FROM phoenix.rails_commands")
      assert c.job.args == payload

      assert [[true]] ==
               rows("SELECT native_fallback FROM phoenix.import_handoffs WHERE event_id=$1", [
                 Ecto.UUID.dump!(c.job.args["event_id"])
               ])

      assert Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert :ok == module.resume(ScratchRepo, c.job, :legacy)
      assert [[kind]] == F.reverse()
    end
  end
end
