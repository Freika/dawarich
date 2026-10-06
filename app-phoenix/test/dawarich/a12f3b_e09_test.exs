defmodule Dawarich.A12f3bE09Test do
  use Dawarich.JobsCase

  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{GpxHandover, Lease, NormalHandover, ProcessWorker}
  alias Dawarich.Jobs.{Drain, Ownership, Processed}

  setup do: F.setup()

  @tag a12f3b_case: "E09a"
  test "E09 native owner accepts every retained argument and continuation shape", base do
    for source <- [4, 3], status <- [3, 2] do
      c = checkpoint(base, source)

      rows("UPDATE imports SET status=$2,raw_data=$3 WHERE id=$1", [
        c.import.id,
        status,
        %{"waypoints_seen" => 1}
      ])

      rows(
        "UPDATE phoenix.import_runs SET phase='terminal',attachment_snapshot=$2 WHERE import_id=$1",
        [c.import.id, %{"attachment" => nil}]
      )

      rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
      c = %{c | job: %{c.job | attempt: 2}}
      assert :ok = c.handover.resume(ScratchRepo, c.job)
      assert Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [[^status]] = rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      assert [] = F.reverse()
      assert [] = rows("SELECT event_id FROM phoenix.import_handoffs")

      children =
        rows("SELECT worker,args FROM oban.oban_jobs WHERE state IN ('available','scheduled')")

      assert length(children) == if(status == 2 and source == 4, do: 1, else: 0)

      if status == 2 and source == 4 do
        assert [
                 [
                   "Dawarich.EnhancedImport.ExtractGpxWorker",
                   %{"import_id" => id, "lock_attempt" => 1}
                 ]
               ] = children

        assert id == c.import.id
      end

      if status == 2 and source == 3 do
        assert [[4]] =
                 rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
                   c.import.id
                 ])
      end

      assert :ok = c.handover.resume(ScratchRepo, c.job)

      assert children ==
               rows(
                 "SELECT worker,args FROM oban.oban_jobs WHERE state IN ('available','scheduled')"
               )
    end
  end

  @tag a12f3b_case: "E09b"
  test "E09 source accepted chain remains visible until all children settle", base do
    for source <- [4, 3] do
      c = checkpoint(base, source)

      rows("UPDATE imports SET status=2,raw_data=$2 WHERE id=$1", [
        c.import.id,
        %{"waypoints_seen" => 1}
      ])

      assert {:snooze, 5} = c.handover.resume(ScratchRepo, c.job)
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert [] = F.reverse()
      assert "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons

      rows(
        "UPDATE phoenix.import_runs SET phase='terminal',attachment_snapshot=$2 WHERE import_id=$1",
        [c.import.id, %{"attachment" => nil}]
      )

      if source == 4 do
        rows(
          "CREATE FUNCTION public.e09_reject_child() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.worker='Dawarich.EnhancedImport.ExtractGpxWorker' THEN RAISE EXCEPTION 'E09 child unavailable'; END IF; RETURN NEW; END $$"
        )

        rows(
          "CREATE TRIGGER e09_reject_child BEFORE INSERT ON oban.oban_jobs FOR EACH ROW EXECUTE FUNCTION public.e09_reject_child()"
        )

        try do
          assert_raise Postgrex.Error, ~r/E09 child unavailable/, fn ->
            c.handover.resume(ScratchRepo, c.job)
          end

          refute Processed.done?(ScratchRepo, c.job.args["event_id"])

          assert [[0]] =
                   rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
                     c.import.id
                   ])
        after
          rows("DROP TRIGGER e09_reject_child ON oban.oban_jobs")
          rows("DROP FUNCTION public.e09_reject_child()")
        end
      end

      assert :ok = c.handover.resume(ScratchRepo, c.job)
      rows("UPDATE oban.oban_jobs SET state='completed' WHERE id=$1", [c.job.id])
      status = Drain.status(ScratchRepo)
      assert status.counts.incomplete_oban == if(source == 4, do: 1, else: 0)
      if source == 4, do: assert("incomplete_oban" in status.shutdown_reasons)
      assert [] = F.reverse()
      rows("UPDATE oban.oban_jobs SET state='completed' WHERE state IN ('available','scheduled')")
      refute "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    end
  end

  defp checkpoint(base, source) do
    reset!(ScratchRepo)
    c = Map.merge(base, Dawarich.ImportLeaseFixture.create())
    rows("UPDATE imports SET source=$2 WHERE id=$1", [c.import.id, source])
    rows("UPDATE users SET settings=$2 WHERE id=$1", [c.import.user_id, %{"locale" => "fr"}])

    opts =
      if source == 4 do
        []
      else
        rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
          c.job.id
        ])

        Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)
        ProcessWorker.lease_options()
      end

    assert {:ok, :ok} = Lease.with_import(ScratchRepo, c.job, c.import, fn _ -> :ok end, opts)
    Map.put(c, :handover, if(source == 4, do: GpxHandover, else: NormalHandover))
  end
end
