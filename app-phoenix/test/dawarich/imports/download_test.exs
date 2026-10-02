defmodule Dawarich.Imports.DownloadTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.Download

  setup do
    f = Dawarich.ImportLeaseFixture.create()
    root = Path.join(System.tmp_dir!(), "download-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    context = %{services: %{"local" => %{service: "local", root: root}}, temp_dir: root}
    Map.merge(f, %{root: root, context: context})
  end

  defp attach(c, bytes, filename \\ "original.gpx", metadata \\ %{}, attachment \\ "file") do
    key = Dawarich.Storage.generate_key()
    path = Dawarich.Storage.disk_path(c.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,byte_size,checksum,service_name,metadata,created_at) VALUES ($1,$2,'application/gpx+xml',$3,$4,'local',$5,now()) RETURNING id",
        [
          key,
          filename,
          byte_size(bytes),
          Base.encode64(:crypto.hash(:md5, bytes)),
          Jason.encode!(metadata)
        ]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,$2,$3,now())",
      [c.import.id, attachment, id]
    )

    id
  end

  defp archive(c, entries) do
    path = Path.join(c.root, "fixture.zip")
    Dawarich.GpxZipFixture.write!(path, entries)
    bytes = File.read!(path)
    File.rm!(path)
    bytes
  end

  defp read(c, user \\ nil) do
    Download.with_file(ScratchRepo, user || c.import.user_id, c.import.id, c.context, fn path,
                                                                                         name,
                                                                                         type ->
      assert File.stat!(path).mode |> Bitwise.band(0o777) == 0o600
      {File.read!(path), name, type}
    end)
  end

  defp prepare(c, source),
    do: Download.prepare!(ScratchRepo, c.import.user_id, c.import.id, source, c.context)

  defp clean(c),
    do:
      assert(
        Enum.flat_map(["import-*", "unzipped-*"], &Path.wildcard(Path.join(c.root, &1))) == []
      )

  test "plain verified file uses visible renamed name and exists throughout callback", c do
    attach(c, "<gpx/>")
    rows("UPDATE imports SET name='holiday.gpx' WHERE id=$1", [c.import.id])
    assert {:ok, {"<gpx/>", "holiday.gpx", "application/gpx+xml"}} = read(c)
    clean(c)
  end

  test "foreign owner and absent attachment return not-found before transfer", c do
    assert {:error, :not_found} = read(c)
    attach(c, "<gpx/>")
    assert {:error, :not_found} = read(c, c.other)
    clean(c)
  end

  test "unknown or mismatched service hands back before download", c do
    source = attach(c, "<gpx/>")
    rows("UPDATE active_storage_blobs SET service_name='elsewhere' WHERE id=$1", [source])
    assert {:legacy, :unconfigured_storage_service} = read(c)
    clean(c)
  end

  test "checksum corruption never invokes callback or retains temporary file", c do
    source = attach(c, "<gpx/>")

    rows("UPDATE active_storage_blobs SET checksum='AAAAAAAAAAAAAAAAAAAAAA==' WHERE id=$1", [
      source
    ])

    assert_raise RuntimeError, "Checksum mismatch", fn -> read(c) end
    clean(c)
  end

  test "storage traversal is rejected without reading arbitrary files", c do
    source = attach(c, "<gpx/>")
    rows("UPDATE active_storage_blobs SET key='../private' WHERE id=$1", [source])
    assert {:legacy, :unsafe_storage_key} = read(c)
    clean(c)
  end

  test "wrapped single file is pending then prepared once, retaining original", c do
    zipped = archive(c, [{"original.gpx", "<gpx/>", [flags: 8]}])

    source =
      attach(c, zipped, "original.gpx.zip", %{
        "dawarich_client_wrapped" => true,
        "dawarich_original_filename" => "original.gpx"
      })

    assert {:error, :pending} = read(c)
    assert :ok = prepare(c, source)
    assert {:ok, {"<gpx/>", "lease.gpx", "application/gpx+xml"}} = read(c)

    assert [[prepared]] =
             rows(
               "SELECT blob_id FROM active_storage_attachments WHERE record_id=$1 AND name='prepared_download'",
               [c.import.id]
             )

    assert :ok = prepare(c, source)

    assert [[^prepared]] =
             rows(
               "SELECT blob_id FROM active_storage_attachments WHERE record_id=$1 AND name='prepared_download'",
               [c.import.id]
             )

    assert [[^source]] =
             rows(
               "SELECT blob_id FROM active_storage_attachments WHERE record_id=$1 AND name='file'",
               [c.import.id]
             )

    clean(c)
  end

  test "legacy wrapping heuristic and deduplicated rename preserve extension", c do
    source = attach(c, archive(c, [{"ride.gpx", "<gpx/>", []}]), "ride.gpx.zip")
    rows("UPDATE imports SET name='ride.gpx_20260101_120000.zip' WHERE id=$1", [c.import.id])
    assert :ok = prepare(c, source)
    assert {:ok, {"<gpx/>", "ride_20260101_120000.gpx", "application/gpx+xml"}} = read(c)
    clean(c)
  end

  test "explicit false marker suppresses legacy unwrap", c do
    zipped = archive(c, [{"original.gpx", "<gpx/>", []}])
    attach(c, zipped, "original.gpx.zip", %{"dawarich_client_wrapped" => false})
    assert {:ok, {^zipped, "lease.gpx", "application/gpx+xml"}} = read(c)
    clean(c)
  end

  test "explicit original download serves verified archive while prepared cache is pending", c do
    zipped = archive(c, [{"ride.gpx", "<gpx/>", []}])
    attach(c, zipped, "ride.gpx.zip")
    original = %{c | context: Map.put(c.context, :original?, true)}
    assert {:ok, {^zipped, "lease.gpx.zip", "application/gpx+xml"}} = read(original)
    assert {:error, :pending} = read(c)
    clean(c)
  end

  for {label, entries} <- [
        {"multi entry", [{"ride.gpx", "<gpx/>", []}, {"two.gpx", "<gpx/>", []}]},
        {"metadata name mismatch", [{"different.gpx", "<gpx/>", []}]},
        {"profile v1", [{"data.json", ~s({"counts":{},"settings":{}}), []}]}
      ] do
    test "#{label} downloads retained original archive after preparation", c do
      zipped = archive(c, unquote(Macro.escape(entries)))

      source =
        attach(c, zipped, "ride.gpx.zip", %{
          "dawarich_client_wrapped" => true,
          "dawarich_original_filename" => "ride.gpx"
        })

      assert :ok = prepare(c, source)

      assert [[^source]] =
               rows(
                 "SELECT blob_id FROM active_storage_attachments WHERE record_id=$1 AND name='prepared_download'",
                 [c.import.id]
               )

      assert {:ok, {^zipped, "lease.gpx.zip", "application/gpx+xml"}} = read(c)
      clean(c)
    end
  end

  test "a prepared attachment for an old source remains pending", c do
    source = attach(c, archive(c, [{"ride.gpx", "<gpx/>", []}]), "ride.gpx.zip")

    attach(
      c,
      "old",
      "old.gpx",
      %{"dawarich_download_source_blob_id" => source + 1},
      "prepared_download"
    )

    assert {:error, :pending} = read(c)
    clean(c)
  end

  test "invalid archive inspection and mismatched corrupt inner retain original", c do
    for zipped <- ["PK\x03\x04broken", archive(c, [{"wrong.gpx", "<gpx/>", [crc: 0]}])] do
      rows("DELETE FROM active_storage_attachments WHERE record_id=$1", [c.import.id])

      source =
        attach(c, zipped, "ride.gpx.zip", %{
          "dawarich_client_wrapped" => true,
          "dawarich_original_filename" => "ride.gpx"
        })

      assert :ok = prepare(c, source)
      assert {:ok, {^zipped, "lease.gpx.zip", _}} = read(c)
      clean(c)
    end
  end

  test "oversize unwrap falls back to original and generic JSON unwrap remains bounded", c do
    zipped = archive(c, [{"ride.gpx", "<gpx/>", []}])
    source = attach(c, zipped, "ride.gpx.zip")
    limited = %{c | context: Map.put(c.context, :archive_opts, max_bytes: 2)}
    assert :ok = prepare(limited, source)
    assert {:ok, {^zipped, "lease.gpx.zip", _}} = read(c)
    rows("DELETE FROM active_storage_attachments WHERE record_id=$1", [c.import.id])
    source = attach(c, archive(c, [{"ride.json", "{\"points\":[]}", []}]), "ride.json.zip")
    assert :ok = prepare(c, source)
    assert {:ok, {"{\"points\":[]}", "lease.gpx", "application/json"}} = read(c)
    clean(c)
  end

  test "matching corrupt inner propagates extraction error without preparing cache", c do
    source = attach(c, archive(c, [{"ride.gpx", "<gpx/>", [crc: 0]}]), "ride.gpx.zip")
    assert_raise Dawarich.Imports.GpxArchive.Error, fn -> prepare(c, source) end

    assert [[0]] =
             rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_id=$1 AND name='prepared_download'",
               [c.import.id]
             )

    clean(c)
  end

  test "attachment publication and terminal callback rollback atomically", c do
    source = attach(c, archive(c, [{"ride.gpx", "<gpx/>", []}]), "ride.gpx.zip")
    context = Map.put(c.context, :on_terminal, fn -> raise "terminal failure" end)

    assert_raise RuntimeError, "terminal failure", fn ->
      prepare(%{c | context: context}, source)
    end

    assert [[0]] =
             rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_id=$1 AND name='prepared_download'",
               [c.import.id]
             )

    assert [[1]] = rows("SELECT count(*) FROM active_storage_blobs")
    assert length(Path.wildcard(Path.join([c.root, "*", "*", "*"]))) == 1
    clean(c)
  end

  test "stale source skips and guarded publication honors lost fence", c do
    source = attach(c, archive(c, [{"ride.gpx", "<gpx/>", []}]), "ride.gpx.zip")
    assert :ok = prepare(c, source + 1)
    context = Map.put(c.context, :fence, fn _ -> raise Dawarich.Imports.LeaseLost end)
    assert_raise Dawarich.Imports.LeaseLost, fn -> prepare(%{c | context: context}, source) end
    assert [[1]] = rows("SELECT count(*) FROM active_storage_blobs")
    clean(c)
  end

  test "stored-service alias persists on prepared cache and remains readable", c do
    source = attach(c, archive(c, [{"ride.gpx", "<gpx/>", []}]), "ride.gpx.zip")
    rows("UPDATE active_storage_blobs SET service_name='test' WHERE id=$1", [source])

    context = %{
      c.context
      | services: %{"test" => %{service: "local", stored_service: "test", root: c.root}}
    }

    assert :ok = prepare(%{c | context: context}, source)

    assert [["test"]] =
             rows(
               "SELECT b.service_name FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.name='prepared_download' AND a.record_id=$1",
               [c.import.id]
             )

    assert {:ok, {"<gpx/>", "lease.gpx", "application/gpx+xml"}} = read(%{c | context: context})
    clean(c)
  end

  test "stale prepared replacement captures immutable purge receipt and durable effect", c do
    source = attach(c, archive(c, [{"ride.gpx", "<gpx/>", []}]), "ride.gpx.zip")

    old =
      attach(
        c,
        "old",
        "old.gpx",
        %{"dawarich_download_source_blob_id" => source + 1},
        "prepared_download"
      )

    assert :ok = prepare(c, source)

    assert [[c.import.id, c.import.user_id, source]] ==
             rows(
               "SELECT import_id,user_id,source_blob_id FROM phoenix.import_blob_purges WHERE blob_id=$1",
               [old]
             )

    assert [[payload]] =
             rows(
               "SELECT payload FROM phoenix.rails_commands WHERE kind='imports.prepared_download_purge'"
             )

    assert payload == %{
             "blob_id" => old,
             "import_id" => c.import.id,
             "user_id" => c.import.user_id,
             "source_blob_id" => source
           }

    assert [[0]] = rows("SELECT count(*) FROM active_storage_attachments WHERE blob_id=$1", [old])
    clean(c)
  end

  test "shared stale prepared blob detaches without binding foreign owner's final purge", c do
    source = attach(c, archive(c, [{"ride.gpx", "<gpx/>", []}]), "ride.gpx.zip")

    old =
      attach(
        c,
        "old",
        "old.gpx",
        %{"dawarich_download_source_blob_id" => source + 1},
        "prepared_download"
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('User',$1,'avatar',$2,now())",
      [c.other, old]
    )

    assert :ok = prepare(c, source)
    assert [[0]] = rows("SELECT count(*) FROM phoenix.import_blob_purges WHERE blob_id=$1", [old])

    assert [[0]] =
             rows(
               "SELECT count(*) FROM phoenix.rails_commands WHERE kind='imports.prepared_download_purge'"
             )

    assert [[1]] = rows("SELECT count(*) FROM active_storage_attachments WHERE blob_id=$1", [old])
    clean(c)
  end

  test "purge receipts reject unowned attachments and preserve unrelated receipt", c do
    source = attach(c, "<gpx/>")

    assert_raise ArgumentError, "Unowned purge attachment", fn ->
      ScratchRepo.transaction(fn ->
        Dawarich.Imports.ImportBlobPurges.authorize!(
          ScratchRepo,
          c.import.id,
          c.other,
          source,
          source
        )
      end)
    end

    rows(
      "INSERT INTO phoenix.import_blob_purges(blob_id,import_id,user_id,source_blob_id) VALUES ($1,$2,$3,$1)",
      [source, c.import.id, c.other]
    )

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Dawarich.Imports.ImportBlobPurges.authorize!(
                 ScratchRepo,
                 c.import.id,
                 c.import.user_id,
                 source,
                 source
               )
             end)

    assert Enum.sort([[c.other], [c.import.user_id]]) ==
             Enum.sort(
               rows("SELECT user_id FROM phoenix.import_blob_purges WHERE blob_id=$1", [source])
             )
  end

  test "same-user blob reattachment to another import adds immutable current authorization", c do
    source = attach(c, "<gpx/>")

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Dawarich.Imports.ImportBlobPurges.authorize!(
                 ScratchRepo,
                 c.import.id,
                 c.import.user_id,
                 source,
                 source
               )
             end)

    rows("DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1", [
      c.import.id
    ])

    [[id]] =
      rows(
        "INSERT INTO imports(user_id,name,source,created_at,updated_at) VALUES ($1,'reuse.gpx',4,now(),now()) RETURNING id",
        [c.import.user_id]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'file',$2,now())",
      [id, source]
    )

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               Dawarich.Imports.ImportBlobPurges.authorize!(
                 ScratchRepo,
                 id,
                 c.import.user_id,
                 source,
                 source
               )
             end)

    assert Enum.sort([[c.import.id, c.import.user_id, source], [id, c.import.user_id, source]]) ==
             Enum.sort(
               rows(
                 "SELECT import_id,user_id,source_blob_id FROM phoenix.import_blob_purges WHERE blob_id=$1",
                 [source]
               )
             )
  end

  test "changed attachment after actual blocked storage read denies transfer", c do
    bytes = "<gpx/>"
    source = attach(c, bytes)
    rows("UPDATE active_storage_blobs SET service_name='s3' WHERE id=$1", [source])
    parent = self()

    {url, server} =
      Dawarich.Test.DownloadServer.start(fn socket, _, _ ->
        send(parent, {:reading, self()})
        receive do: (:release -> :ok)

        Dawarich.Test.RawHTTP.reply(
          socket,
          "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
            bytes
        )
      end)

    on_exit(fn -> send(server.pid, :release) end)

    config =
      Map.merge(
        %{service: "s3"},
        Dawarich.Storage.S3.config!(%{
          "AWS_ACCESS_KEY_ID" => "AKIA_SYNTHETIC",
          "AWS_SECRET_ACCESS_KEY" => "synthetic",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "dawarich",
          "AWS_ENDPOINT" => url
        })
      )

    context = %{c.context | services: %{"s3" => config}}

    task =
      Task.async(fn ->
        Download.with_file(ScratchRepo, c.import.user_id, c.import.id, context, fn _, _, _ ->
          flunk("changed identity reached callback")
        end)
      end)

    assert_receive {:reading, reader}, 3000
    rows("UPDATE active_storage_blobs SET filename='replacement.gpx' WHERE id=$1", [source])
    send(reader, :release)
    assert {:error, :not_found} = Task.await(task)
    clean(c)
  end

  test "changed source after blocked preparation read returns changed outside a network transaction",
       c do
    bytes = archive(c, [{"ride.gpx", "<gpx/>", []}])
    source = attach(c, bytes, "ride.gpx.zip")
    rows("UPDATE active_storage_blobs SET service_name='s3' WHERE id=$1", [source])
    parent = self()

    {url, server} =
      Dawarich.Test.DownloadServer.start(fn socket, _, _ ->
        send(parent, {:preparing, self()})
        receive do: (:release -> :ok)

        Dawarich.Test.RawHTTP.reply(
          socket,
          "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
            bytes
        )
      end)

    on_exit(fn -> send(server.pid, :release) end)

    config =
      Map.merge(
        %{service: "s3"},
        Dawarich.Storage.S3.config!(%{
          "AWS_ACCESS_KEY_ID" => "AKIA_SYNTHETIC",
          "AWS_SECRET_ACCESS_KEY" => "synthetic",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "dawarich",
          "AWS_ENDPOINT" => url
        })
      )

    context = %{c.context | services: %{"s3" => config}}
    task = Task.async(fn -> prepare(%{c | context: context}, source) end)
    assert_receive {:preparing, reader}, 3000
    rows("UPDATE active_storage_blobs SET filename='replacement.gpx.zip' WHERE id=$1", [source])
    send(reader, :release)
    assert {:error, :changed} = Task.await(task)

    assert [[0]] =
             rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_id=$1 AND name='prepared_download'",
               [c.import.id]
             )

    clean(c)
  end

  test "the prepared-download upload runs outside the fence: the user's points and locks proceed",
       c do
    {context, source} = blocked_upload(c)
    task = Task.async(fn -> prepare(%{c | context: context}, source) end)
    assert_receive {:uploading, writer, _}, 3000

    assert {:ok, :ok} =
             ScratchRepo.transaction(fn ->
               rows("SET LOCAL lock_timeout = '2s'")

               rows(
                 "INSERT INTO points(user_id,timestamp,lonlat,created_at,updated_at) VALUES($1,100,ST_SetSRID(ST_MakePoint(12.37,51.34),4326)::geography,now(),now())",
                 [c.import.user_id]
               )

               rows("SELECT 1 FROM users WHERE id=$1 FOR NO KEY UPDATE NOWAIT", [c.import.user_id])

               rows("SELECT 1 FROM imports WHERE id=$1 FOR UPDATE NOWAIT", [c.import.id])
               :ok
             end)

    send(writer, :release)
    assert :ok = Task.await(task)

    assert [[1]] =
             rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_id=$1 AND name='prepared_download'",
               [c.import.id]
             )
  end

  test "a source change during the upload refuses the attach and deletes the uploaded candidate",
       c do
    {context, source} = blocked_upload(c)
    context = Map.delete(context, :fence)
    task = Task.async(fn -> prepare(%{c | context: context}, source) end)
    assert_receive {:uploading, writer, put}, 3000

    ScratchRepo.transaction(fn ->
      rows("SET LOCAL lock_timeout = '2s'")
      rows("UPDATE active_storage_blobs SET filename='replacement.gpx.zip' WHERE id=$1", [source])
    end)

    send(writer, :release)
    assert {:error, :changed} = Task.await(task)
    assert_receive {:deleted, ^put}, 3000

    assert [[0]] =
             rows(
               "SELECT count(*) FROM active_storage_attachments WHERE record_id=$1 AND name='prepared_download'",
               [c.import.id]
             )

    assert [[1]] = rows("SELECT count(*) FROM active_storage_blobs")
  end

  defp blocked_upload(c) do
    bytes = archive(c, [{"ride.gpx", "<gpx/>", []}])
    source = attach(c, bytes, "ride.gpx.zip")
    rows("UPDATE active_storage_blobs SET service_name='s3' WHERE id=$1", [source])
    parent = self()
    server = Dawarich.Test.RawHTTP.listen()

    Task.start_link(fn ->
      Dawarich.Test.DownloadServer.serve(server, fn socket, line ->
        case String.split(line, " ") do
          ["GET" | _] ->
            Dawarich.Test.RawHTTP.reply(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
                bytes
            )

          ["PUT", path | _] ->
            send(parent, {:uploading, self(), path})
            receive do: (:release -> :ok)

            Dawarich.Test.RawHTTP.reply(
              socket,
              "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            )

          ["DELETE", path | _] ->
            send(parent, {:deleted, path})

            Dawarich.Test.RawHTTP.reply(
              socket,
              "HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n"
            )
        end
      end)
    end)

    config =
      Map.merge(
        %{service: "s3"},
        Dawarich.Storage.S3.config!(%{
          "AWS_ACCESS_KEY_ID" => "AKIA_SYNTHETIC",
          "AWS_SECRET_ACCESS_KEY" => "synthetic",
          "AWS_REGION" => "eu-central-1",
          "AWS_BUCKET" => "dawarich",
          "AWS_ENDPOINT" => "http://127.0.0.1:#{server.port}"
        })
      )

    fence = fn fun ->
      {:ok, value} =
        ScratchRepo.transaction(fn ->
          rows(
            "SELECT 1 FROM imports i JOIN users u ON u.id=i.user_id WHERE i.id=$1 FOR UPDATE OF i FOR SHARE OF u",
            [c.import.id]
          )

          fun.()
        end)

      value
    end

    {%{c.context | services: %{"s3" => config}} |> Map.put(:fence, fence), source}
  end

  test "callback failure and cancellation clean adopted verified files", c do
    attach(c, "<gpx/>")

    assert_raise RuntimeError, "callback failure", fn ->
      Download.with_file(ScratchRepo, c.import.user_id, c.import.id, c.context, fn _, _, _ ->
        raise "callback failure"
      end)
    end

    clean(c)
    parent = self()

    pid =
      spawn(fn ->
        Download.with_file(ScratchRepo, c.import.user_id, c.import.id, c.context, fn path, _, _ ->
          send(parent, {:verified, path})
          receive do: (:never -> :ok)
        end)
      end)

    assert_receive {:verified, path}, 3000
    Process.exit(pid, :kill)
    deadline = System.monotonic_time(:millisecond) + 1000
    await_removed(path, deadline)
    clean(c)
  end

  defp await_removed(path, deadline) do
    if File.exists?(path) do
      assert System.monotonic_time(:millisecond) < deadline
      Process.sleep(10)
      await_removed(path, deadline)
    end
  end
end
