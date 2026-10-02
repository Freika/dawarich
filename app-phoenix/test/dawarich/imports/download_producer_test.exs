defmodule Dawarich.Imports.DownloadProducerTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.DownloadProducer

  setup do
    c = Dawarich.ImportLeaseFixture.create()
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.prepare_download", :oban)

    rows(
      "CREATE TABLE IF NOT EXISTS phoenix.import_download_requests(import_id bigint NOT NULL,source_blob_id bigint NOT NULL,requested_at timestamptz NOT NULL,event_id uuid NOT NULL,PRIMARY KEY(import_id,source_blob_id))"
    )

    rows("TRUNCATE phoenix.import_download_requests")

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES('abcdefgh','a.gpx.zip','application/zip','{}','local',3,'abc',now()) RETURNING id"
      )

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Import',$1,$2,now())",
      [c.import.id, blob]
    )

    Map.put(c, :blob, blob)
  end

  test "one rolling-minute native prepare command survives duplicate GET and later retries", c do
    now = DateTime.utc_now()

    assert {:ok, :queued} =
             DownloadProducer.enqueue(ScratchRepo, c.import.user_id, c.import.id, c.blob, now)

    assert {:ok, :cached} =
             DownloadProducer.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               c.blob,
               DateTime.add(now, 59)
             )

    assert [[payload]] = rows("SELECT payload FROM job_outbox")

    assert payload == %{
             "import_id" => c.import.id,
             "user_id" => c.import.user_id,
             "source_blob_id" => c.blob
           }

    assert {:ok, :queued} =
             DownloadProducer.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               c.blob,
               DateTime.add(now, 61)
             )

    assert [[2]] = rows("SELECT count(*) FROM job_outbox")
  end

  test "current Sidekiq owner uses guarded reverse handoff and future receipt remains cached",
       c do
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.prepare_download", :sidekiq)
    now = DateTime.utc_now()

    assert {:ok, :queued} =
             DownloadProducer.enqueue(ScratchRepo, c.import.user_id, c.import.id, c.blob, now)

    assert [["imports.prepare_download", _]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    rows("UPDATE phoenix.import_download_requests SET requested_at=now()+interval '1 day'")

    assert {:ok, :cached} =
             DownloadProducer.enqueue(ScratchRepo, c.import.user_id, c.import.id, c.blob, now)
  end

  test "cross-owner and replaced source attachment cannot queue or cache a preparation", c do
    assert {:error, :not_found} =
             DownloadProducer.enqueue(
               ScratchRepo,
               c.other,
               c.import.id,
               c.blob,
               DateTime.utc_now()
             )

    assert {:error, :not_found} =
             DownloadProducer.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               c.blob + 1,
               DateTime.utc_now()
             )

    assert [] == rows("SELECT * FROM phoenix.import_download_requests")
  end
end
