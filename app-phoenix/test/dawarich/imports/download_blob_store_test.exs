defmodule Dawarich.Imports.DownloadBlobStoreTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.Download.BlobStore

  setup do
    root = Path.join(System.tmp_dir!(), "blob-store-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    path = Path.join(root, "inner.gpx")
    File.write!(path, "<gpx/>")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: path, config: %{service: "local", stored_service: "test", root: root}}
  end

  test "local publication stages on the destination filesystem before the publication callback",
       c do
    storage = Path.join(c.root, "separate-storage-mount")
    config = %{c.config | root: storage}

    BlobStore.with_candidate(
      ScratchRepo,
      config,
      c.path,
      "ride.gpx",
      "application/gpx+xml",
      fn put ->
        assert [stage] = Path.wildcard(Path.join([storage, "*", "*", "download-candidate-*"]))
        assert File.read!(stage) == "<gpx/>"
        assert Bitwise.band(File.stat!(stage).mode, 0o777) == 0o600
        assert File.stat!(stage).major_device == File.stat!(storage).major_device
        assert Path.wildcard(Path.join(c.root, "download-candidate-*")) == []
        blob = put.()
        assert Path.dirname(stage) == Path.dirname(Dawarich.Storage.disk_path(storage, blob.key))
        assert File.read!(Dawarich.Storage.disk_path(storage, blob.key)) == "<gpx/>"
        assert blob.checksum == Base.encode64(:crypto.hash(:md5, "<gpx/>"))
        assert blob.byte_size == 6
      end
    )

    assert File.read!(c.path) == "<gpx/>"
    assert Path.wildcard(Path.join([storage, "*", "*", "*"])) == []
  end

  test "process kill after publication before DB commit removes known candidate", c do
    parent = self()

    pid =
      spawn(fn ->
        BlobStore.with_candidate(
          ScratchRepo,
          c.config,
          c.path,
          "ride.gpx",
          "application/gpx+xml",
          fn put ->
            blob = put.()
            send(parent, {:published, blob})
            receive do: (:never -> :ok)
          end
        )
      end)

    assert_receive {:published, blob}, 3000
    path = Dawarich.Storage.disk_path(c.root, blob.key)
    assert File.read!(path) == "<gpx/>"
    Process.exit(pid, :kill)
    await_removed(path)
    assert Path.wildcard(Path.join(c.root, "download-candidate-*")) == []
  end

  test "process kill after actual attachment commit retains referenced candidate", c do
    f = Dawarich.ImportLeaseFixture.create()
    parent = self()

    pid =
      spawn(fn ->
        BlobStore.with_candidate(
          ScratchRepo,
          c.config,
          c.path,
          "ride.gpx",
          "application/gpx+xml",
          fn put ->
            blob = put.()

            {:ok, :ok} =
              ScratchRepo.transaction(fn ->
                [[id]] =
                  ScratchRepo.query!(
                    "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES ($1,$2,$3,'{}',$4,$5,$6,now()) RETURNING id",
                    [
                      blob.key,
                      blob.filename,
                      blob.content_type,
                      blob.service_name,
                      blob.byte_size,
                      blob.checksum
                    ],
                    log: false
                  ).rows

                ScratchRepo.query!(
                  "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'prepared_download',$2,now())",
                  [f.import.id, id],
                  log: false
                )

                :ok
              end)

            send(parent, {:committed, blob})
            receive do: (:never -> :ok)
          end
        )
      end)

    assert_receive {:committed, blob}, 3000
    {:monitored_by, [guard]} = Process.info(pid, :monitored_by)
    guard_ref = Process.monitor(guard)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^guard_ref, :process, ^guard, :normal}, 5_000
    assert File.read!(Dawarich.Storage.disk_path(c.root, blob.key)) == "<gpx/>"
    assert blob.service_name == "test"
    assert Path.wildcard(Path.join(c.root, "download-candidate-*")) == []
  end

  test "error callback removes stored candidate but leaves caller's verified input", c do
    assert_raise RuntimeError, "abort", fn ->
      BlobStore.with_candidate(
        ScratchRepo,
        c.config,
        c.path,
        "ride.gpx",
        "application/gpx+xml",
        fn put ->
          put.()
          raise "abort"
        end
      )
    end

    assert Path.wildcard(Path.join([c.root, "*", "*", "*"])) == []
    assert File.read!(c.path) == "<gpx/>"
    assert Path.wildcard(Path.join(c.root, "download-candidate-*")) == []
  end

  test "in-flight actual S3 PUT is drained after owner kill before known-key DELETE", c do
    parent = self()

    {url, server} =
      Dawarich.Test.DownloadServer.start(
        fn socket, head, index ->
          case index do
            1 ->
              assert head =~ "PUT "
              send(parent, {:put_started, self()})
              receive do: (:complete_put -> :ok)

              Dawarich.Test.RawHTTP.reply(
                socket,
                "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
              )

            2 ->
              assert head =~ "DELETE "
              send(parent, :candidate_deleted)

              Dawarich.Test.RawHTTP.reply(
                socket,
                "HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
              )
          end
        end,
        2
      )

    config =
      Map.merge(
        %{service: "s3", root: c.root},
        Dawarich.Storage.S3.config!(%{
          "AWS_ACCESS_KEY_ID" => "AKIA_SYNTHETIC",
          "AWS_SECRET_ACCESS_KEY" => "synthetic",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "dawarich",
          "AWS_ENDPOINT" => url
        })
      )

    pid =
      spawn(fn ->
        BlobStore.with_candidate(
          ScratchRepo,
          config,
          c.path,
          "ride.gpx",
          "application/gpx+xml",
          fn put -> put.() end
        )
      end)

    assert_receive {:put_started, http}, 3000
    Process.exit(pid, :kill)
    refute_receive :candidate_deleted, 50
    send(http, :complete_put)
    assert_receive :candidate_deleted, 3000
    Task.await(server)
    await_stage_removed(c.root)
  end

  defp await_stage_removed(root, n \\ 100) do
    if Path.wildcard(Path.join(root, "download-candidate-*")) != [] do
      assert n > 0
      Process.sleep(10)
      await_stage_removed(root, n - 1)
    end
  end

  defp await_removed(path, n \\ 100) do
    if File.exists?(path) do
      assert n > 0
      Process.sleep(10)
      await_removed(path, n - 1)
    end
  end
end
