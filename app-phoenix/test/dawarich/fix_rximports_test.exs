defmodule Dawarich.FixRximportsTest do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.{DestroyWorker, ManualExtraction}
  setup do: F.setup()

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

  defp assert_failed(id) do
    assert [[4, true]] ==
             rows(
               "SELECT additional_data_extraction_status,(additional_data_extraction->>'error_message') LIKE 'Removing extracted data failed:%' FROM imports WHERE id=$1",
               [id]
             )
  end
end
