defmodule Dawarich.PendingImports.PurgeWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.Ownership
  alias Dawarich.PendingImports.{CleanupWorker, PurgeWorker}
  alias Dawarich.Storage

  @oban __MODULE__.Oban
  @now ~U[2026-10-04 12:00:00Z]

  defmodule FakeClient do
    @behaviour ExAws.Request.HttpClient
    def request(_, _, _, _, opts), do: Keyword.fetch!(opts, :respond).()
  end

  setup do
    start_oban(@oban)
    root = Path.join(System.tmp_dir!(), "a12d3-purge-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "a failed object delete retains recoverable cleanup work and retry cannot purge a newly shared blob",
       %{root: root} do
    for service <- ["test", "s3"] do
      reset!(ScratchRepo)

      rows(
        "INSERT INTO pending_imports (id,original_filename,origin,expires_at,created_at,updated_at) VALUES (48901,'synthetic.zip','https://example.invalid','2026-10-03',now(),now())"
      )

      rows(
        "INSERT INTO active_storage_blobs (id,key,filename,service_name,byte_size,created_at) VALUES (48500,'a12d3purgeobject','synthetic.zip',$1,30,now())",
        [service]
      )

      rows(
        "INSERT INTO active_storage_attachments (id,name,record_type,record_id,blob_id,created_at) VALUES (48501,'file','PendingImport',48901,48500,now())"
      )

      path = Storage.disk_path(root, "a12d3purgeobject")
      File.mkdir_p!(path)
      services = %{services: %{service => storage(service, root, 403)}}
      Ownership.put!(ScratchRepo, "cron:pending_imports_cleanup", :oban)
      assert CleanupWorker.run(ScratchRepo, @oban, @now, services: services) == :ok

      assert [[args]] =
               rows(
                 "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.PendingImports.PurgeWorker'"
               )

      assert Map.take(args, ~w(pending_import_id blob_id attachment_id)) == %{
               "pending_import_id" => 48901,
               "blob_id" => 48500,
               "attachment_id" => 48501
             }

      Ownership.put!(ScratchRepo, "cron:pending_imports_cleanup", :sidekiq, pinned: true)
      assert {:error, _} = PurgeWorker.run(ScratchRepo, args, services: services)
      assert rows("SELECT count(*) FROM pending_imports") == [[1]]
      assert rows("SELECT count(*) FROM active_storage_attachments") == [[1]]
      assert rows("SELECT count(*) FROM active_storage_blobs") == [[1]]

      rows(
        "INSERT INTO active_storage_attachments (id,name,record_type,record_id,blob_id,created_at) VALUES (48502,'file','Import',48902,48500,now())"
      )

      assert PurgeWorker.run(ScratchRepo, args, services: services) == :ok
      assert rows("SELECT count(*) FROM pending_imports") == [[0]]
      assert rows("SELECT record_type FROM active_storage_attachments") == [["Import"]]
      assert rows("SELECT count(*) FROM active_storage_blobs") == [[1]]
      assert File.dir?(path)
      assert PurgeWorker.run(ScratchRepo, args, services: services) == :ok

      rows(
        "INSERT INTO pending_imports (id,original_filename,origin,expires_at,created_at,updated_at) VALUES (48901,'synthetic.zip','https://example.invalid','2026-10-03',now(),now())"
      )

      rows(
        "INSERT INTO active_storage_attachments (id,name,record_type,record_id,blob_id,created_at) VALUES (48503,'file','PendingImport',48901,48500,now())"
      )

      assert PurgeWorker.run(ScratchRepo, args, services: services) == :ok
      assert rows("SELECT count(*) FROM pending_imports") == [[1]]
      rows("DELETE FROM active_storage_attachments WHERE id=48502")
      File.rmdir!(path)
      File.write!(path, "synthetic")

      assert PurgeWorker.run(ScratchRepo, Map.put(args, "attachment_id", 48503),
               services: %{services: %{service => storage(service, root, 204)}}
             ) == :ok

      assert rows("SELECT count(*) FROM pending_imports") == [[0]]
      assert rows("SELECT count(*) FROM active_storage_blobs") == [[0]]
      if service == "test", do: refute(File.exists?(path)), else: File.rm!(path)
    end
  end

  defp storage("test", root, _), do: %{service: "local", root: root}

  defp storage("s3", root, status) do
    c =
      Storage.config!(
        %{
          "STORAGE_BACKEND" => "s3",
          "AWS_ACCESS_KEY_ID" => "AKIA",
          "AWS_SECRET_ACCESS_KEY" => "synthetic",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "synthetic"
        },
        root
      )

    %{
      c
      | ex_aws:
          Keyword.merge(c.ex_aws,
            http_client: FakeClient,
            retry: [max_attempts: 1],
            http_opts: [respond: fn -> {:ok, %{status_code: status, headers: [], body: ""}} end]
          )
    }
  end
end
