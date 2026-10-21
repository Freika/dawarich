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
    test "#{lane} settles natively without reverse work in both modes", c do
      for mode <- ["on", "off"] do
        reset!(ScratchRepo)
        c = Map.merge(c, Dawarich.ImportLeaseFixture.create())
        rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, unquote(source)])
        rows("UPDATE oban.oban_jobs SET worker=$2 WHERE id=$1", [c.job.id, unquote(worker)])
        for entry <- Registry.entries(), do: Ownership.put!(ScratchRepo, entry.key, :oban)
        System.put_env("DAWARICH_RAILS", mode)
        assert :ok == unquote(module).resume(ScratchRepo, c.job, :legacy)
        assert [] == F.reverse()
        assert [] == rows("SELECT event_id FROM phoenix.import_handoffs")
        assert Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
        assert [[3]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
        assert :ok == unquote(module).resume(ScratchRepo, c.job, :legacy)

        assert [[1]] ==
                 rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])
      end
    end

    @tag a12f3b_case: selector
    test "#{lane} preserves byte-identical Rails-owned resume", c do
      kind = unquote(kind)
      rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, unquote(source)])
      rows("UPDATE oban.oban_jobs SET worker=$2 WHERE id=$1", [c.job.id, unquote(worker)])
      System.put_env("DAWARICH_RAILS", "on")
      Ownership.put!(ScratchRepo, "command:" <> unquote(lane), :sidekiq, pinned: true)
      assert :ok == unquote(module).resume(ScratchRepo, c.job, :legacy)

      assert [[^kind, payload, bytes]] =
               rows("SELECT kind,payload,payload::text FROM phoenix.rails_commands")

      assert c.job.args == payload

      assert bytes ==
               "{\"user_id\": #{c.import.user_id}, \"event_id\": \"#{c.job.args["event_id"]}\", \"import_id\": #{c.import.id}, \"time_zone\": \"#{c.job.args["time_zone"]}\"}"

      assert [[true]] ==
               rows("SELECT native_fallback FROM phoenix.import_handoffs WHERE event_id=$1", [
                 Ecto.UUID.dump!(c.job.args["event_id"])
               ])

      assert [[0]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      assert [] == rows("SELECT id FROM notifications")
      assert Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert :ok == unquote(module).resume(ScratchRepo, c.job, :legacy)
      assert [[kind]] == F.reverse()
    end
  end
end
