defmodule Dawarich.PendingImports.CleanupWorkerTest do
  use Dawarich.JobsCase

  alias Dawarich.Jobs.Ownership
  alias Dawarich.PendingImports.CleanupWorker
  alias Dawarich.Storage

  @oban __MODULE__.Oban
  @fixture Path.expand("../../fixtures/a12d3/schedules.json", __DIR__)
  @now ~U[2026-10-04 12:00:00Z]

  setup do
    start_oban(@oban)
    root = Path.join(System.tmp_dir!(), "a12d3-pending-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{services: %{services: %{"test" => %{service: "local", root: root}}}, root: root}
  end

  test "cleanup matches expiry and seven-day rules while retaining every live shared attachment",
       %{services: services, root: root} do
    cases = Jason.decode!(File.read!(@fixture))["classes"]["PendingImports::CleanupJob"]["cases"]

    for f <- Enum.reject(cases, &(&1["id"] == "failed_delete")) do
      reset!(ScratchRepo)
      rows("DELETE FROM pending_imports")
      input = f["input"]
      expires = datetime(input["expires_at"])
      claimed = if input["claimed_at"], do: datetime(input["claimed_at"])

      rows(
        "INSERT INTO pending_imports (id,original_filename,origin,expires_at,claimed_at,created_at,updated_at) VALUES (48901,'synthetic.zip','https://example.invalid',$1,$2,now(),now())",
        [expires, claimed]
      )

      key = "a12d3pending#{String.replace(f["id"], "_", "")}"
      path = Storage.disk_path(root, key)
      attached = f["id"] != "missing_file"

      if attached do
        rows(
          "INSERT INTO active_storage_blobs (id,key,filename,service_name,byte_size,created_at) VALUES (48500,$1,'synthetic.zip','test',30,now())",
          [key]
        )

        rows(
          "INSERT INTO active_storage_attachments (id,name,record_type,record_id,blob_id,created_at) VALUES (48501,'file','PendingImport',48901,48500,now())"
        )

        File.mkdir_p!(Path.dirname(path))
        if f["id"] != "missing_object", do: File.write!(path, "synthetic pending-import bytes")
      end

      if f["import_attached"] do
        rows(
          "INSERT INTO active_storage_attachments (id,name,record_type,record_id,blob_id,created_at) VALUES (48502,'file','Import',48902,48500,now())"
        )
      end

      Ownership.put!(ScratchRepo, "cron:pending_imports_cleanup", :oban)
      assert CleanupWorker.run(ScratchRepo, @oban, @now, services: services) == :ok

      for [args] <-
            rows(
              "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.PendingImports.PurgeWorker'"
            ) do
        assert Dawarich.PendingImports.PurgeWorker.run(ScratchRepo, args, services: services) ==
                 :ok
      end

      assert rows("SELECT EXISTS(SELECT 1 FROM pending_imports WHERE id=48901)") == [
               [f["pending_exists"]]
             ]

      assert rows("SELECT record_type,record_id FROM active_storage_attachments ORDER BY id") ==
               f["attachments"]

      retained = attached and (f["pending_exists"] or f["import_attached"] == true)

      assert rows("SELECT EXISTS(SELECT 1 FROM active_storage_blobs WHERE id=48500)") == [
               [retained]
             ]

      assert File.exists?(path) == retained
      assert CleanupWorker.run(ScratchRepo, @oban, @now, services: services) == :ok
      assert File.exists?(path) == retained
      File.rm(path)
    end

    reset!(ScratchRepo)
    rows("DELETE FROM pending_imports")

    rows(
      "INSERT INTO pending_imports (id,original_filename,origin,expires_at,created_at,updated_at) SELECT n,'synthetic.zip','https://example.invalid',$1,now(),now() FROM generate_series(50001,51001) n",
      [datetime("2026-10-03T12:00:00Z")]
    )

    Ownership.put!(ScratchRepo, "cron:pending_imports_cleanup", :oban)
    assert CleanupWorker.run(ScratchRepo, @oban, @now, services: services) == :ok
    assert rows("SELECT count(*) FROM pending_imports") == [[1]]

    assert [[next]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.PendingImports.CleanupWorker'"
             )

    assert next["after_id"] == 51_000

    assert CleanupWorker.run(ScratchRepo, @oban, @now,
             services: services,
             after_id: next["after_id"]
           ) == :ok

    assert rows("SELECT count(*) FROM pending_imports") == [[0]]
  end

  defp datetime(value) do
    {:ok, date, _} = DateTime.from_iso8601(value)
    DateTime.to_naive(date)
  end
end
