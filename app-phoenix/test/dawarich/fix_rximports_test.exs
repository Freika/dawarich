defmodule Dawarich.FixRximportsTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{DestroyWorker, ManualExtraction}
  setup do: F.setup()

  @tag a12f3b_case: "F2"
  test "completion rollback emits no owner event", c do
    c = F.destroy(c)
    Dawarich.Imports.Events.subscribe(c.import.user_id)

    rows(
      "CREATE FUNCTION public.posthoc_reject_receipt() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN IF NEW.handler='imports.destroy' THEN RAISE EXCEPTION 'synthetic terminal commit failure'; END IF; RETURN NEW; END$$"
    )

    rows(
      "CREATE CONSTRAINT TRIGGER posthoc_reject_receipt AFTER INSERT ON phoenix.processed_commands DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.posthoc_reject_receipt()"
    )

    try do
      assert_raise Postgrex.Error, fn -> DestroyWorker.perform(c.job) end
    after
      rows("DROP TRIGGER posthoc_reject_receipt ON phoenix.processed_commands")
      rows("DROP FUNCTION public.posthoc_reject_receipt()")
    end

    assert [] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
    refute Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
    drain_events()
    assert_receive :imports_changed
    refute_received :imports_changed
    assert length(event_jobs()) == 1

    assert [] ==
             rows(
               "SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker'"
             )

    assert :ok == DestroyWorker.perform(c.job)
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert length(event_jobs()) == 2
    refute_received :imports_changed
    drain_events()
    assert_receive :imports_changed
    refute_received :imports_changed

    assert :ok == DestroyWorker.perform(c.job)
    drain_events()
    assert length(event_jobs()) == 2
    refute_received :imports_changed
  end

  @tag a12f3b_case: "F2-status"
  test "deleting status rollback emits no owner event", c do
    c = F.destroy(c)
    Dawarich.Imports.Events.subscribe(c.import.user_id)

    assert {:ok, :ok} ==
             F.with_destroy(c, fn lease ->
               rows(
                 "CREATE FUNCTION public.posthoc_reject_status() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'synthetic status commit failure'; END$$"
               )

               rows(
                 "CREATE CONSTRAINT TRIGGER posthoc_reject_status AFTER UPDATE ON imports DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public.posthoc_reject_status()"
               )

               try do
                 assert_raise Postgrex.Error, fn ->
                   Dawarich.Imports.DestroyLease.effect!(lease, fn ->
                     rows("UPDATE imports SET processed=7 WHERE id=$1", [c.import.id])
                     Dawarich.Imports.DestroyEffects.status!(lease)
                   end)
                 end
               after
                 rows("DROP TRIGGER posthoc_reject_status ON imports")
                 rows("DROP FUNCTION public.posthoc_reject_status()")
               end

               :ok
             end)

    assert event_jobs() == []
    assert [[0]] == rows("SELECT processed FROM imports WHERE id=$1", [c.import.id])
    drain_events()
    refute_received :imports_changed

    assert {:ok, :ok} ==
             F.with_destroy(c, fn lease ->
               Dawarich.Imports.DestroyEffects.status!(lease)
               refute_received :imports_changed
               :ok
             end)

    [[args]] = event_jobs()

    assert {:ok, :ok} ==
             ScratchRepo.transaction(fn ->
               assert_raise ArgumentError,
                            "import notification requires a committed intent",
                            fn ->
                              Dawarich.Imports.EventsWorker.run(ScratchRepo, args)
                            end

               :ok
             end)

    refute_received :imports_changed
    drain_events()
    assert_receive :imports_changed
    refute_received :imports_changed

    assert {:ok, :ok} ==
             F.with_destroy(c, fn lease ->
               Dawarich.Imports.DestroyEffects.status!(lease)
             end)

    assert [[args]] == event_jobs()
    drain_events()
    refute_received :imports_changed

    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    retry = %{c | job: %{c.job | attempt: 2}}

    assert {:ok, :ok} ==
             F.with_destroy(retry, fn lease ->
               Dawarich.Imports.DestroyEffects.status!(lease)
             end)

    [[^args], [next]] = event_jobs()
    refute args["event_id"] == next["event_id"]
    drain_events()
    assert_receive :imports_changed
    refute_received :imports_changed
  end

  @tag a12f3b_case: "F3"
  test "unavailable storage retains blob metadata until physical purge succeeds", c do
    c = F.destroy(c)
    blob = F.blob(c, "source.gpx", "<gpx/>", "file")
    Application.put_env(:dawarich, :imports_services, %{})
    assert :ok == DestroyWorker.perform(c.job)
    assert [] == rows("SELECT id FROM imports WHERE id=$1", [c.import.id])
    assert Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.PreparedDownloadPurgeWorker'"
      )

    assert {:error, :unconfigured_storage_service} ==
             Dawarich.Imports.PreparedDownloadPurgeWorker.perform(%Oban.Job{args: args})

    assert File.exists?(Dawarich.Storage.disk_path(c.root, blob.key))
    assert [[blob.id]] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
    [[metadata]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob.id])
    assert Dawarich.Storage.NativePurge.pending?(metadata)

    Application.put_env(:dawarich, :imports_services, %{
      "local" => %{service: "local", root: c.root}
    })

    assert :ok == Dawarich.Imports.PreparedDownloadPurgeWorker.perform(%Oban.Job{args: args})
    assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
    refute File.exists?(Dawarich.Storage.disk_path(c.root, blob.key))
    assert :ok == Dawarich.Imports.PreparedDownloadPurgeWorker.perform(%Oban.Job{args: args})
  end

  @tag a12f3b_case: "F1"
  test "extraction removal failure records the Rails failed state and error", c do
    context = %{c.context | now: DateTime.utc_now()}

    rows("UPDATE imports SET status=2,additional_data_extraction_status=3 WHERE id=$1", [
      c.import.id
    ])

    rows(
      "INSERT INTO tracks(user_id,import_id,original_path,start_at,end_at,created_at,updated_at) VALUES($1,$2,ST_GeomFromText('LINESTRING(13 52,13.01 52.01)',4326),now(),now(),now(),now())",
      [c.import.user_id, c.import.id]
    )

    assert {:ok, :queued} ==
             ManualExtraction.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               :remove,
               %{},
               context
             )

    [[id, args]] =
      rows(
        "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.ExtractionRemovalWorker'"
      )

    rows("UPDATE oban.oban_jobs SET state='executing',attempt=26 WHERE id=$1", [id])

    rows(
      "CREATE FUNCTION public.posthoc_reject_track() RETURNS trigger LANGUAGE plpgsql AS $$BEGIN RAISE EXCEPTION 'synthetic removal failure'; END$$"
    )

    rows(
      "CREATE TRIGGER posthoc_reject_track BEFORE DELETE ON tracks FOR EACH ROW EXECUTE FUNCTION public.posthoc_reject_track()"
    )

    job = %Oban.Job{id: id, attempt: 26, max_attempts: 26, args: args}

    retry_job =
      try do
        assert_raise Postgrex.Error, fn ->
          Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, job)
        end

        refute Dawarich.Jobs.Processed.done?(ScratchRepo, args["event_id"])
        assert_failed(c.import.id)

        assert {:ok, :queued} ==
                 ManualExtraction.enqueue(
                   ScratchRepo,
                   c.import.user_id,
                   c.import.id,
                   :remove,
                   %{},
                   context
                 )

        [[next_id, next_args]] =
          rows(
            "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.ExtractionRemovalWorker' AND id<>$1",
            [id]
          )

        refute next_args["event_id"] == args["event_id"]

        assert {:cancel, :changed_import} ==
                 Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, job)

        rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [next_id])
        next = %Oban.Job{id: next_id, attempt: 1, max_attempts: 26, args: next_args}

        assert_raise Postgrex.Error, fn ->
          Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, next)
        end

        assert_failed(c.import.id)
        next
      after
        rows("DROP TRIGGER posthoc_reject_track ON tracks")
        rows("DROP FUNCTION public.posthoc_reject_track()")
      end

    assert :ok == Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, retry_job)

    assert [[0]] ==
             rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
               c.import.id
             ])

    assert Dawarich.Jobs.Processed.done?(ScratchRepo, retry_job.args["event_id"])
    assert :ok == Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, retry_job)
  end

  defp drain_events do
    for [args] <- event_jobs() do
      assert :ok == apply(Dawarich.Imports.EventsWorker, :perform, [%Oban.Job{args: args}])
    end
  end

  defp event_jobs,
    do:
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.EventsWorker' ORDER BY id"
      )

  defp assert_failed(id) do
    assert [[4, true]] ==
             rows(
               "SELECT additional_data_extraction_status,(additional_data_extraction->>'error_message') LIKE 'Removing extracted data failed:%' FROM imports WHERE id=$1",
               [id]
             )
  end
end
