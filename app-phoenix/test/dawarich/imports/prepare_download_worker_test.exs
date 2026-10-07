defmodule Dawarich.Imports.PrepareDownloadWorkerTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.PrepareDownloadWorker
  alias Dawarich.Jobs.{Ownership, Processed, Dispatch}

  setup do
    c = Dawarich.ImportLeaseFixture.create()
    root = Path.join(System.tmp_dir!(), "download-worker-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    config = %{service: "local", root: root}

    for {key, value} <- [jobs_repo: ScratchRepo, imports_services: %{"local" => config}] do
      previous = Application.fetch_env(:dawarich, key)
      Application.put_env(:dawarich, key, value)

      on_exit(fn ->
        case previous do
          {:ok, configured} -> Application.put_env(:dawarich, key, configured)
          :error -> Application.delete_env(:dawarich, key)
        end
      end)
    end

    on_exit(fn -> File.rm_rf!(root) end)
    Ownership.put!(ScratchRepo, "command:imports.prepare_download", :oban)
    rows("DELETE FROM oban.oban_jobs WHERE id=$1", [c.job.id])
    Map.merge(c, %{root: root, config: config})
  end

  defp attach(c, wrapped? \\ true, entries \\ [{"ride.gpx", "<gpx/>", [method: 8]}]) do
    path = Path.join(c.root, "fixture.zip")
    content = "<gpx/>"

    if wrapped?,
      do: Dawarich.GpxZipFixture.write!(path, entries),
      else: File.write!(path, content)

    blob =
      Dawarich.Storage.put!(
        c.config,
        path,
        if(wrapped?, do: "ride.gpx.zip", else: "ride.gpx"),
        "application/zip"
      )

    metadata =
      Jason.encode!(%{
        "dawarich_client_wrapped" => wrapped?,
        "dawarich_original_filename" => "ride.gpx"
      })

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,byte_size,checksum,service_name,metadata,created_at) VALUES($1,$2,$3,$4,$5,$6,now()) RETURNING id",
        [blob.key, blob.filename, blob.byte_size, blob.checksum, blob.service_name, metadata]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'file',$2,now())",
      [c.import.id, id]
    )

    id
  end

  defp job(c, blob) do
    args = %{
      "event_id" => Ecto.UUID.generate(),
      "import_id" => c.import.id,
      "user_id" => c.import.user_id,
      "source_blob_id" => blob
    }

    [[id]] =
      rows(
        "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,attempted_at) VALUES('executing','imports','Dawarich.Imports.PrepareDownloadWorker',$1,1,3,now()) RETURNING id",
        [args]
      )

    %Oban.Job{id: id, attempt: 1, args: args}
  end

  test "exact envelope rejects extra, nonpositive and unsupported versions", c do
    valid = %{"import_id" => c.import.id, "user_id" => c.import.user_id, "source_blob_id" => 1}
    assert {:ok, ^valid} = PrepareDownloadWorker.args_from_command(1, valid)
    assert {:error, "unsupported_version"} = PrepareDownloadWorker.args_from_command(2, valid)

    for payload <- [
          Map.put(valid, "extra", 1),
          Map.put(valid, "source_blob_id", 0),
          Map.put(valid, "user_id", -1)
        ] do
      assert {:error, "invalid_payload"} = PrepareDownloadWorker.args_from_command(1, payload)
    end
  end

  test "actual dispatch and drain publishes verified prepared cache and processed atomically",
       c do
    blob = attach(c)

    event =
      outbox!(
        command_type: "imports.prepare_download",
        payload: %{
          "import_id" => c.import.id,
          "user_id" => c.import.user_id,
          "source_blob_id" => blob
        }
      )

    start_oban(__MODULE__)

    assert %{dispatched: 1} =
             Dispatch.run(
               now: Dawarich.JobsCase.db_now(ScratchRepo),
               oban: __MODULE__,
               repo: ScratchRepo
             )

    assert %{success: 1, failure: 0} = Oban.drain_queue(__MODULE__, queue: :imports)

    assert [[key, metadata]] =
             rows(
               "SELECT b.key,b.metadata FROM active_storage_attachments a JOIN active_storage_blobs b ON b.id=a.blob_id WHERE a.record_type='Import' AND a.record_id=$1 AND a.name='prepared_download'",
               [c.import.id]
             )

    assert File.read!(Dawarich.Storage.disk_path(c.root, key)) == "<gpx/>"
    assert Jason.decode!(metadata)["dawarich_download_source_blob_id"] == blob
    assert Processed.done?(ScratchRepo, event)
  end

  test "cancelled and obsolete attempts neither publish nor consume", c do
    j = job(c, attach(c))
    rows("UPDATE oban.oban_jobs SET state='cancelled' WHERE id=$1", [j.id])
    assert {:cancel, _} = PrepareDownloadWorker.perform(j)
    refute Processed.done?(ScratchRepo, j.args["event_id"])
    rows("UPDATE oban.oban_jobs SET state='executing',attempt=2 WHERE id=$1", [j.id])
    assert {:cancel, _} = PrepareDownloadWorker.perform(j)
    refute Processed.done?(ScratchRepo, j.args["event_id"])
  end

  test "changed source and foreign actor are consumed without prepared publication", c do
    j = job(c, attach(c))

    rows("UPDATE active_storage_attachments SET name='elsewhere' WHERE record_id=$1", [
      c.import.id
    ])

    assert :ok = PrepareDownloadWorker.perform(j)
    assert Processed.done?(ScratchRepo, j.args["event_id"])
    assert [] == rows("SELECT id FROM active_storage_attachments WHERE name='prepared_download'")
    other = job(c, 1)

    rows("UPDATE oban.oban_jobs SET args=jsonb_set(args,'{user_id}',$2) WHERE id=$1", [
      other.id,
      Jason.encode!(c.other)
    ])

    assert {:cancel, _} = PrepareDownloadWorker.perform(other)
    refute Processed.done?(ScratchRepo, other.args["event_id"])
  end

  test "late sidekiq ownership creates one durable fallback then consumes", c do
    j = job(c, attach(c))
    Ownership.put!(ScratchRepo, "command:imports.prepare_download", :sidekiq)
    assert :ok = PrepareDownloadWorker.perform(j)

    assert [["imports.prepare_download", payload]] =
             rows("SELECT kind,payload FROM phoenix.rails_commands")

    assert payload["native_fallback"] == true
    assert payload["source_blob_id"] == j.args["source_blob_id"]
    assert Processed.done?(ScratchRepo, j.args["event_id"])
    assert :ok = PrepareDownloadWorker.perform(j)
    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "marker failure rolls back prepared rows and removes the published storage orphan", c do
    j = job(c, attach(c))
    before = Path.wildcard(Path.join(c.root, "**/*")) |> Enum.filter(&File.regular?/1)

    rows(
      "CREATE FUNCTION reject_download_marker() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'marker unavailable'; END $$"
    )

    rows(
      "CREATE TRIGGER reject_download_marker BEFORE INSERT ON phoenix.processed_commands FOR EACH ROW EXECUTE FUNCTION reject_download_marker()"
    )

    try do
      assert_raise Postgrex.Error, fn -> PrepareDownloadWorker.perform(j) end

      assert [] ==
               rows("SELECT id FROM active_storage_attachments WHERE name='prepared_download'")

      refute Processed.done?(ScratchRepo, j.args["event_id"])
      assert Path.wildcard(Path.join(c.root, "**/*")) |> Enum.filter(&File.regular?/1) == before
    after
      rows("DROP TRIGGER reject_download_marker ON phoenix.processed_commands")
      rows("DROP FUNCTION reject_download_marker()")
    end

    assert :ok = PrepareDownloadWorker.perform(j)
    assert Processed.done?(ScratchRepo, j.args["event_id"])
  end

  test "unsupported catalog retains a native retry without preparing or reversing", c do
    j = job(c, attach(c))
    Application.put_env(:dawarich, :imports_services, %{})
    assert {:error, :unconfigured_storage_service} = PrepareDownloadWorker.perform(j)
    refute Processed.done?(ScratchRepo, j.args["event_id"])
    assert [] == rows("SELECT payload FROM phoenix.rails_commands")
    assert [] == rows("SELECT id FROM active_storage_attachments WHERE name='prepared_download'")
  end

  test "another live preparation snoozes and releases cleanly", c do
    j = job(c, attach(c))
    foreign_lease!("import-download:#{c.import.id}")
    assert {:snooze, 5} = PrepareDownloadWorker.perform(j)
    refute Processed.done?(ScratchRepo, j.args["event_id"])
    end_foreign_lease!("import-download:#{c.import.id}")
    assert :ok = PrepareDownloadWorker.perform(j)
  end

  defp s3_config(c, url) do
    Map.merge(
      %{service: "s3", root: c.root},
      Dawarich.Storage.S3.config!(%{
        "AWS_ACCESS_KEY_ID" => "synthetic",
        "AWS_SECRET_ACCESS_KEY" => "synthetic",
        "AWS_REGION" => "eu-central-1",
        "AWS_BUCKET" => "dawarich",
        "AWS_ENDPOINT" => url
      })
    )
  end

  for change <- [:owner, :cancel, :user, :attachment, :rename, :rename_original] do
    test "#{change} changed during blocked HTTP download fences prepared publication", c do
      blob =
        if unquote(change) == :rename_original,
          do: attach(c, true, [{"ride.gpx", "<gpx/>", []}, {"two.gpx", "<gpx/>", []}]),
          else: attach(c)

      j = job(c, blob)

      [[key, size, checksum]] =
        rows("SELECT key,byte_size,checksum FROM active_storage_blobs WHERE id=$1", [blob])

      bytes = File.read!(Dawarich.Storage.disk_path(c.root, key))
      parent = self()

      {url, server} =
        Dawarich.Test.DownloadServer.start(fn socket, _, _ ->
          send(parent, :downloading)
          receive do: (:release -> :ok)

          Dawarich.Test.RawHTTP.reply(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Length: #{size}\r\nConnection: close\r\n\r\n" <> bytes
          )
        end)

      on_exit(fn -> send(server.pid, :release) end)

      config = s3_config(c, url)

      rows("UPDATE active_storage_blobs SET service_name='s3' WHERE id=$1", [blob])
      Application.put_env(:dawarich, :imports_services, %{"s3" => config})
      task = Task.async(fn -> PrepareDownloadWorker.perform(j) end)
      receive do: (:downloading -> :ok)

      case unquote(change) do
        :owner ->
          Ownership.put!(ScratchRepo, "command:imports.prepare_download", :sidekiq)

        :cancel ->
          rows("UPDATE oban.oban_jobs SET state='cancelled' WHERE id=$1", [j.id])

        :user ->
          rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.import.user_id])

        :attachment ->
          rows("UPDATE active_storage_blobs SET checksum=$2 WHERE id=$1", [blob, "different"])

        rename when rename in [:rename, :rename_original] ->
          rows("UPDATE imports SET name='renamed.gpx' WHERE id=$1", [c.import.id])
      end

      send(server.pid, :release)
      result = Task.await(task, :infinity)
      Task.await(server, :infinity)

      assert [] ==
               rows("SELECT id FROM active_storage_attachments WHERE name='prepared_download'")

      assert [] == rows("SELECT id FROM notifications")

      if unquote(change) == :cancel,
        do: assert(match?({:cancel, _}, result)),
        else: assert(result in [:ok, {:snooze, 5}])

      if unquote(change) in [:rename, :rename_original], do: assert(result == {:snooze, 5})

      if unquote(change) in [:cancel, :attachment, :rename, :rename_original],
        do: refute(Processed.done?(ScratchRepo, j.args["event_id"])),
        else: assert(Processed.done?(ScratchRepo, j.args["event_id"]))

      assert File.read!(Dawarich.Storage.disk_path(c.root, key)) == bytes
      assert checksum == Base.encode64(:crypto.hash(:md5, bytes))
    end
  end

  test "a rename during the prepared upload hands back as changed and deletes the candidate", c do
    blob = attach(c)
    j = job(c, blob)
    [[key]] = rows("SELECT key FROM active_storage_blobs WHERE id=$1", [blob])
    bytes = File.read!(Dawarich.Storage.disk_path(c.root, key))
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

    rows("UPDATE active_storage_blobs SET service_name='s3' WHERE id=$1", [blob])

    Application.put_env(:dawarich, :imports_services, %{
      "s3" => s3_config(c, "http://127.0.0.1:#{server.port}")
    })

    task = Task.async(fn -> PrepareDownloadWorker.perform(j) end)
    {:uploading, writer, put} = receive do: ({:uploading, _, _} = message -> message)
    rows("UPDATE imports SET name='renamed.gpx' WHERE id=$1", [c.import.id])
    send(writer, :release)

    assert {:snooze, 5} = Task.await(task, :infinity)
    assert_received {:deleted, ^put}
    assert [] == rows("SELECT id FROM active_storage_attachments WHERE name='prepared_download'")
    assert [[1]] = rows("SELECT count(*) FROM active_storage_blobs")
    refute Processed.done?(ScratchRepo, j.args["event_id"])
  end
end
