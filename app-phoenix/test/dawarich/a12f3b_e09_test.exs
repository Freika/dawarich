defmodule Dawarich.A12f3bE09Test do
  use Dawarich.JobsCase

  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{GpxHandover, Lease, NormalHandover, ProcessGpxWorker, ProcessWorker}
  alias Dawarich.Jobs.{Drain, Ownership, Processed}

  setup do: F.setup()

  @tag a12f3b_case: "E09a"
  test "E09 native owner accepts every retained argument and continuation shape", base do
    for {source, status} <- [{4, 2}, {3, 3}, {3, 2}] do
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

      assert length(children) == if(status == 2, do: 1, else: 0)

      if status == 2 do
        assert [["Dawarich.EnhancedImport.NormalWorker", args]] = children

        assert Map.drop(args, ["event_id"]) == %{
                 "import_id" => c.import.id,
                 "user_id" => c.import.user_id,
                 "source" => source,
                 "source_blob_id" => nil,
                 "time_zone" => "Europe/Berlin",
                 "locale" => "fr",
                 "lock_attempt" => 1
               }

        assert {:ok, _} = Ecto.UUID.cast(args["event_id"])

        assert [[1, args["event_id"], "extract"]] ==
                 rows(
                   "SELECT additional_data_extraction_status,additional_data_extraction->>'phoenix_extraction_event',additional_data_extraction->>'phoenix_extraction_action' FROM imports WHERE id=$1",
                   [c.import.id]
                 )
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
          "CREATE FUNCTION public.e09_reject_child() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.worker='Dawarich.EnhancedImport.NormalWorker' THEN RAISE EXCEPTION 'E09 child unavailable'; END IF; RETURN NEW; END $$"
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
      assert status.counts.incomplete_oban == 1
      assert "incomplete_oban" in status.shutdown_reasons
      assert [] = F.reverse()
      rows("UPDATE oban.oban_jobs SET state='completed' WHERE state IN ('available','scheduled')")
      refute "incomplete_oban" in Drain.status(ScratchRepo).shutdown_reasons
    end
  end

  @tag a12f3b_case: "R1"
  test "R1 real GPX failure survives marker rejection without processing or notifying twice", c do
    rows("CREATE TABLE public.e09_failure_passes (import_id bigint)")

    rows(
      "CREATE FUNCTION public.e09_record_failure() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.status=3 THEN INSERT INTO public.e09_failure_passes VALUES (NEW.id); END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER e09_record_failure AFTER UPDATE OF status ON imports FOR EACH ROW EXECUTE FUNCTION public.e09_record_failure()"
    )

    rows(
      "CREATE FUNCTION public.e09_reject_marker() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'E09 marker unavailable'; END $$"
    )

    try do
      for recovery <- [:worker, :handover] do
        if recovery == :handover, do: reset!(ScratchRepo)
        c = if recovery == :handover, do: Dawarich.ImportLeaseFixture.create(), else: c

        rows(
          "CREATE TRIGGER e09_reject_marker BEFORE INSERT ON phoenix.processed_commands FOR EACH ROW EXECUTE FUNCTION public.e09_reject_marker()"
        )

        try do
          assert_raise Postgrex.Error, ~r/E09 marker unavailable/, fn ->
            ProcessGpxWorker.perform(c.job)
          end
        after
          rows("DROP TRIGGER e09_reject_marker ON phoenix.processed_commands")
        end

        assert [[3]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])

        assert [[1]] ==
                 rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])

        refute Processed.done?(ScratchRepo, c.job.args["event_id"])
        rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
        job = %{c.job | attempt: 2}

        assert :ok =
                 if(recovery == :worker,
                   do: ProcessGpxWorker.perform(job),
                   else: GpxHandover.resume(ScratchRepo, job)
                 )

        assert [[1]] ==
                 rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])

        assert [[1]] ==
                 rows("SELECT count(*) FROM public.e09_failure_passes WHERE import_id=$1", [
                   c.import.id
                 ])

        assert [[3, "terminal"]] ==
                 rows(
                   "SELECT i.status,r.phase FROM imports i JOIN phoenix.import_runs r ON r.import_id=i.id WHERE i.id=$1",
                   [c.import.id]
                 )

        assert Processed.done?(ScratchRepo, job.args["event_id"])
        assert :ok = ProcessGpxWorker.perform(job)
        assert :ok = GpxHandover.resume(ScratchRepo, job)

        assert [[1]] ==
                 rows("SELECT count(*) FROM notifications WHERE user_id=$1", [c.import.user_id])

        assert [] == rows("SELECT id FROM points WHERE import_id=$1", [c.import.id])

        assert [] ==
                 rows(
                   "SELECT id FROM oban.oban_jobs WHERE worker IN('Dawarich.EnhancedImport.ExtractGpxWorker','Dawarich.EnhancedImport.NormalWorker')"
                 )

        assert [] == F.reverse()
        assert [] == rows("SELECT event_id FROM phoenix.import_handoffs")
      end
    after
      rows("DROP FUNCTION public.e09_reject_marker()")
      rows("DROP TRIGGER e09_record_failure ON imports")
      rows("DROP FUNCTION public.e09_record_failure()")
      rows("DROP TABLE public.e09_failure_passes")
    end
  end

  @tag a12f3b_case: "R1_atomic"
  test "R1 rejected failure notification leaves processing recoverable without a terminal receipt",
       c do
    rows(
      "CREATE FUNCTION public.e09_reject_notification() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'E09 notification unavailable'; END $$"
    )

    rows(
      "CREATE TRIGGER e09_reject_notification BEFORE INSERT ON notifications FOR EACH ROW EXECUTE FUNCTION public.e09_reject_notification()"
    )

    try do
      assert_raise Postgrex.Error, ~r/E09 notification unavailable/, fn ->
        ProcessGpxWorker.perform(c.job)
      end
    after
      rows("DROP TRIGGER e09_reject_notification ON notifications")
      rows("DROP FUNCTION public.e09_reject_notification()")
    end

    assert [[0, "processing"]] ==
             rows(
               "SELECT i.status,r.phase FROM imports i JOIN phoenix.import_runs r ON r.import_id=i.id WHERE i.id=$1",
               [c.import.id]
             )

    assert [] == rows("SELECT id FROM notifications")
    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert {:snooze, 5} = GpxHandover.resume(ScratchRepo, c.job)

    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    assert :ok = ProcessGpxWorker.perform(%{c.job | attempt: 2})

    assert [[3, "terminal"]] ==
             rows(
               "SELECT i.status,r.phase FROM imports i JOIN phoenix.import_runs r ON r.import_id=i.id WHERE i.id=$1",
               [c.import.id]
             )

    assert [[1]] == rows("SELECT count(*) FROM notifications")
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert [] == F.reverse()
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
