defmodule Dawarich.A12f3bR08Test do
  use Dawarich.JobsCase
  alias Dawarich.A12f3bImportsFixture, as: F
  alias Dawarich.Imports.ImportBlobPurges
  setup do: F.setup()

  @tag a12f3b_case: "R08k01"
  test "imports.upload_created native producer reaches its source terminal effect", c do
    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_gpx", :sidekiq,
      pinned: true
    )

    rows("UPDATE users SET active_until=now()+interval '1 day' WHERE id=$1", [c.import.user_id])

    blob =
      Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "upload.gpx", "<gpx><trk/></gpx>",
        user_id: c.import.user_id
      )

    assert {:ok, [id]} =
             Dawarich.Imports.UploadCreate.create(
               ScratchRepo,
               %{id: c.import.user_id},
               [blob.signed_id],
               %{storage: %{service: "local", root: c.root}, self_hosted?: true}
             )

    assert [] == F.reverse()
    start_oban(__MODULE__)

    assert %{dispatched: 1} ==
             Dawarich.Jobs.Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               repo: ScratchRepo,
               oban: __MODULE__
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :imports)

    assert %{success: 1, failure: 0} =
             Oban.drain_queue(__MODULE__, queue: :imports, with_scheduled: true)

    assert [[2]] == rows("SELECT status FROM imports WHERE id=$1", [id])

    assert {:error, :already_attached} ==
             Dawarich.Imports.UploadCreate.create(
               ScratchRepo,
               %{id: c.import.user_id},
               [blob.signed_id],
               %{storage: %{service: "local", root: c.root}, self_hosted?: true}
             )

    assert [] == F.reverse()
    System.delete_env("DAWARICH_RAILS")

    other =
      Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "coexist.gpx", "<gpx/>",
        user_id: c.import.user_id
      )

    assert {:ok, [_]} =
             Dawarich.Imports.UploadCreate.create(
               ScratchRepo,
               %{id: c.import.user_id},
               [other.signed_id],
               %{storage: %{service: "local", root: c.root}, self_hosted?: true}
             )

    assert [["imports.upload_created"]] == F.reverse()
    System.put_env("DAWARICH_RAILS", "off")
    watcher = Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, "watcher.gpx", "<gpx/>")
    [[before]] = rows("SELECT count(*) FROM job_outbox WHERE command_type='imports.process_gpx'")

    assert {:ok, _} =
             ScratchRepo.transaction(fn ->
               Dawarich.Imports.UploadRecords.insert!(
                 ScratchRepo,
                 %{id: c.import.user_id, status: 0, subscription_source: 0, settings: %{}},
                 %{
                   blob: Map.put(watcher, :byte_size, 6),
                   source: 4,
                   name: "watcher.gpx",
                   metadata: %{}
                 },
                 :sidekiq
               )
             end)

    assert [[before + 1]] ==
             rows("SELECT count(*) FROM job_outbox WHERE command_type='imports.process_gpx'")

    assert [["imports.upload_created"]] == F.reverse()
  end

  @tag a12f3b_case: "R08k02"
  test "imports.prepare_download native producer reaches its source terminal effect", c do
    {:ok, {_, zip}} = :zip.create(~c"source.zip", [{~c"source.gpx", "<gpx/>"}], [:memory])
    source = F.blob(c, "source.gpx.zip", zip, "file")

    rows("UPDATE active_storage_blobs SET metadata=$2 WHERE id=$1", [
      source.id,
      Jason.encode!(%{
        "dawarich_client_wrapped" => true,
        "dawarich_original_filename" => "source.gpx"
      })
    ])

    Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.prepare_download", :sidekiq,
      pinned: true
    )

    assert {:ok, :queued} ==
             Dawarich.Imports.DownloadProducer.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               source.id
             )

    assert [] == F.reverse()
    start_oban(__MODULE__)

    assert %{dispatched: 1} ==
             Dawarich.Jobs.Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               repo: ScratchRepo,
               oban: __MODULE__
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :imports)

    [[key]] =
      rows(
        "SELECT b.key FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_id=$1 AND a.record_type='Import' AND a.name='prepared_download'",
        [c.import.id]
      )

    assert File.read!(Dawarich.Storage.disk_path(c.root, key)) == "<gpx/>"

    assert {:ok, :cached} ==
             Dawarich.Imports.DownloadProducer.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               source.id
             )

    assert [] == F.reverse()
    System.delete_env("DAWARICH_RAILS")

    assert {:ok, :queued} ==
             Dawarich.Imports.DownloadProducer.enqueue(
               ScratchRepo,
               c.import.user_id,
               c.import.id,
               source.id,
               DateTime.add(DateTime.utc_now(), 61)
             )

    assert [["imports.prepare_download"]] == F.reverse()
  end

  @tag a12f3b_case: "R08k03"
  test "imports.prepared_download_purge native producer reaches its source terminal effect", c do
    source = F.blob(c, "source.gpx", "<gpx/>", "file")
    old = F.blob(c, "prepared.gpx", "private prepared data", "prepared_download")

    {:ok, :ok} =
      ScratchRepo.transaction(fn ->
        ImportBlobPurges.enqueue!(ScratchRepo, c.import.id, c.import.user_id, old.id, source.id)
        :ok
      end)

    assert [[old.id]] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [old.id])
    [[metadata]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [old.id])
    assert Dawarich.Storage.NativePurge.pending?(metadata)
    assert [] == F.reverse()
    assert ["Dawarich.Imports.PreparedDownloadPurgeWorker"] == F.workers()
    [[args]] = rows("SELECT args FROM oban.oban_jobs WHERE state='available'")
    assert File.exists?(Dawarich.Storage.disk_path(c.root, old.key))
    Application.put_env(:dawarich, :imports_services, %{})

    assert {:error, :unconfigured_storage_service} ==
             Dawarich.Imports.PreparedDownloadPurgeWorker.perform(%Oban.Job{args: args})

    assert File.exists?(Dawarich.Storage.disk_path(c.root, old.key))

    Application.put_env(:dawarich, :imports_services, %{
      "local" => %{service: "local", root: c.root}
    })

    assert :ok == Dawarich.Imports.PreparedDownloadPurgeWorker.perform(%Oban.Job{args: args})
    assert :ok == Dawarich.Imports.PreparedDownloadPurgeWorker.perform(%Oban.Job{args: args})
    refute File.exists?(Dawarich.Storage.disk_path(c.root, old.key))
    assert File.exists?(Dawarich.Storage.disk_path(c.root, source.key))
    shared = F.blob(c, "shared.gpx", "shared data", "prepared_download")

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Other',$1,'file',$2,now())",
      [c.other, shared.id]
    )

    assert {:ok, {:skip, :shared}} ==
             ScratchRepo.transaction(fn ->
               ImportBlobPurges.enqueue!(
                 ScratchRepo,
                 c.import.id,
                 c.import.user_id,
                 shared.id,
                 source.id
               )
             end)

    assert [[shared.id]] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [shared.id])
    System.delete_env("DAWARICH_RAILS")
    co = F.blob(c, "coexist.gpx", "coexist data", "prepared_download")

    assert {:ok, _} =
             ScratchRepo.transaction(fn ->
               ImportBlobPurges.enqueue!(
                 ScratchRepo,
                 c.import.id,
                 c.import.user_id,
                 co.id,
                 source.id
               )
             end)

    assert [["imports.prepared_download_purge"]] == F.reverse()
  end
end
