defmodule Dawarich.A12f3bR09Test do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.ManualExtraction
  setup do: F.setup()

  @tag a12f3b_case: "R09k01"
  test "imports.extraction_requested native producer reaches its source terminal effect", c do
    rows("UPDATE imports SET source=3,status=2 WHERE id=$1", [c.import.id])

    assert {:error, :unsupported} ==
             ManualExtraction.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               :extract,
               %{},
               c.context
             )

    assert [] == F.reverse()

    assert [[0]] ==
             rows("SELECT additional_data_extraction_status FROM imports WHERE id=$1", [
               c.import.id
             ])

    System.delete_env("DAWARICH_RAILS")

    assert {:ok, :queued} ==
             ManualExtraction.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               :extract,
               %{},
               c.context
             )

    assert [["imports.extraction_requested"]] == F.reverse()
  end

  @tag a12f3b_case: "R09k02"
  test "imports.extraction_destroy_requested native producer reaches its source terminal effect",
       c do
    rows("UPDATE imports SET status=2,additional_data_extraction_status=3 WHERE id=$1", [
      c.import.id
    ])

    [[track]] =
      rows(
        "INSERT INTO tracks(user_id,import_id,original_path,start_at,end_at,created_at,updated_at) VALUES($1,$2,ST_GeomFromText('LINESTRING(13 52,13.01 52.01)',4326),now(),now(),now(),now()) RETURNING id",
        [c.import.user_id, c.import.id]
      )

    rows(
      "INSERT INTO points(user_id,import_id,track_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,100,ST_SetSRID(ST_MakePoint(13,52),4326)::geography,now(),now())",
      [c.import.user_id, c.import.id, track]
    )

    [[retained]] =
      rows(
        "INSERT INTO tracks(user_id,original_path,start_at,end_at,created_at,updated_at) VALUES($1,ST_GeomFromText('LINESTRING(13 52,13.01 52.01)',4326),now()-interval '1 day',now(),now(),now()) RETURNING id",
        [c.import.user_id]
      )

    rows(
      "INSERT INTO points(user_id,import_id,track_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,$3,101,ST_SetSRID(ST_MakePoint(13,52),4326)::geography,now(),now())",
      [c.import.user_id, c.import.id, retained]
    )

    rows(
      "INSERT INTO track_segments(track_id,source,created_at,updated_at) VALUES($1,'gpx',now(),now())",
      [retained]
    )

    System.delete_env("DAWARICH_RAILS")
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:enhanced_import.destroy_gpx", :oban)
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:transportation.reclassify_track", :oban)

    assert {:ok, :queued} ==
             ManualExtraction.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               :remove,
               %{},
               c.context
             )

    assert [] == F.reverse()

    [[id, args]] =
      rows(
        "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.ExtractionRemovalWorker'"
      )

    rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [id])
    job = %Oban.Job{id: id, attempt: 1, args: args}
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [id])

    assert {:cancel, :stale_attempt} ==
             Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, job)

    assert [[track]] == rows("SELECT id FROM tracks WHERE import_id=$1", [c.import.id])
    rows("UPDATE oban.oban_jobs SET attempt=1 WHERE id=$1", [id])
    assert :ok == Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, job)
    assert :ok == Dawarich.Imports.ExtractionRemovalWorker.run(ScratchRepo, job)
    assert [] == rows("SELECT id FROM tracks WHERE import_id=$1", [c.import.id])

    assert [[nil], [retained]] ==
             rows("SELECT track_id FROM points WHERE import_id=$1 ORDER BY timestamp", [
               c.import.id
             ])

    assert [] == rows("SELECT id FROM track_segments WHERE track_id=$1", [retained])
    assert "Dawarich.Transportation.ReclassifyTrackWorker" in F.workers()

    assert [[2, 0]] ==
             rows("SELECT status,additional_data_extraction_status FROM imports WHERE id=$1", [
               c.import.id
             ])

    assert [] == F.reverse()
  end

  @tag a12f3b_case: "R09k03"
  test "imports.resume native producer reaches its source terminal effect", c do
    assert {:error, :unsupported_native_import} ==
             Dawarich.Imports.GpxHandover.resume(ScratchRepo, c.job, :legacy)

    assert [] == F.reverse()
    refute Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
    System.delete_env("DAWARICH_RAILS")
    assert :ok == Dawarich.Imports.GpxHandover.resume(ScratchRepo, c.job, :legacy)
    assert [["imports.resume"]] == F.reverse()
  end

  @tag a12f3b_case: "R09k04"
  test "imports.normal_resume native producer reaches its source terminal effect", c do
    rows("UPDATE imports SET source=10 WHERE id=$1", [c.import.id])

    rows("UPDATE oban.oban_jobs SET worker='Dawarich.Imports.ProcessWorker' WHERE id=$1", [
      c.job.id
    ])

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)

    assert {:error, :unsupported_native_import} ==
             Dawarich.Imports.NormalHandover.resume(ScratchRepo, c.job, :legacy)

    assert [] == F.reverse()
    refute Dawarich.Jobs.Processed.done?(ScratchRepo, c.job.args["event_id"])
    System.delete_env("DAWARICH_RAILS")
    assert :ok == Dawarich.Imports.NormalHandover.resume(ScratchRepo, c.job, :legacy)
    assert [["imports.normal_resume"]] == F.reverse()
  end
end
