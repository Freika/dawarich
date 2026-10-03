defmodule Dawarich.Imports.GpxLifecycleTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.{GpxLifecycle, Lease}
  alias Dawarich.Jobs.Processed

  setup do
    c = Dawarich.ImportLeaseFixture.create()
    root = Path.join(System.tmp_dir!(), "lifecycle-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    context = %{
      repo: ScratchRepo,
      locale: "de",
      zone: "Europe/Berlin",
      now: ~U[2026-01-01 12:00:00Z],
      services: %{"local" => %{service: "local", root: root}},
      temp_dir: root,
      self_hosted?: true,
      on_terminal: fn ->
        Processed.mark!(ScratchRepo, c.job.args["event_id"], "imports.process_gpx")
      end
    }

    Map.merge(c, %{root: root, context: context})
  end

  defp attach(c, bytes, checksum \\ nil) do
    key = Dawarich.Storage.generate_key()
    path = Dawarich.Storage.disk_path(c.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    digest = checksum || Base.encode64(:crypto.hash(:md5, bytes))

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,byte_size,checksum,service_name,created_at) VALUES ($1,'lifecycle.gpx',$2,$3,'local',now()) RETURNING id",
        [key, byte_size(bytes), digest]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'file',$2,now())",
      [c.import.id, blob]
    )
  end

  defp run(c),
    do: Lease.with_import(ScratchRepo, c.job, c.import, &GpxLifecycle.call(&1, c.context))

  defp point(time \\ "2026-01-01T10:00:00Z"),
    do: "<trkpt lat=\"52\" lon=\"13\"><time>#{time}</time></trkpt>"

  defp document(body), do: "<gpx><trk><trkseg>#{body}</trkseg></trk></gpx>"

  defp assert_clean(c),
    do:
      assert(
        Enum.flat_map(["import-*", "unzipped-*"], &Path.wildcard(Path.join(c.root, &1))) == []
      )

  defp zipped(c, entries) do
    path = Path.join(c.root, "fixture.zip")
    Dawarich.GpxZipFixture.write!(path, entries)
    bytes = File.read!(path)
    File.rm!(path)
    bytes
  end

  test "a legacy XML codec is handed back before processing or counter resets", c do
    bytes =
      ~s(<?xml version="1.0" encoding="Windows-1252"?><gpx><trk><name>) <>
        <<233>> <> ~s(</name><trkseg>) <> point() <> "</trkseg></trk></gpx>"

    attach(c, bytes)
    rows("UPDATE imports SET raw_points=9,doubles=4 WHERE id=$1", [c.import.id])
    assert {:ok, {:legacy, :unsupported_encoding}} = run(c)

    assert [[0, 9, 4]] ==
             rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    assert [] == rows("SELECT id FROM points")
    assert [] == rows("SELECT id FROM notifications")
    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert_clean(c)
  end

  test "unsupported storage is handed back before counters, failure or terminal writes", c do
    attach(c, document(point()))
    rows("UPDATE active_storage_blobs SET service_name='unconfigured'")
    rows("UPDATE imports SET raw_points=9,doubles=4 WHERE id=$1", [c.import.id])
    assert {:ok, {:legacy, :unconfigured_storage_service}} = run(c)

    assert [[0, 9, 4]] ==
             rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    assert [] == rows("SELECT id FROM notifications")
    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
  end

  test "declared Disk alias uses its actual reader without marking unsupported", c do
    attach(c, document(point()))
    rows("UPDATE active_storage_blobs SET service_name='test'")
    config = %{service: "local", stored_service: "test", root: c.root}
    context = %{c.context | services: %{"test" => config}}
    assert {:ok, :ok} = run(%{c | context: context})
    assert [[2, 1]] == rows("SELECT status,raw_points FROM imports WHERE id=$1", [c.import.id])
  end

  test "client ZIP attachment runs the actual GPX driver and cleans both files", c do
    attach(c, zipped(c, [{"ride.gpx", document(point()), [method: 8, flags: 8]}]))
    assert {:ok, :ok} = run(c)
    assert [[2, 1]] == rows("SELECT status,raw_points FROM imports WHERE id=$1", [c.import.id])
    assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert_clean(c)
  end

  test "multi-entry legacy archive returns before processing and terminal consumption", c do
    attach(c, zipped(c, [{"one.gpx", document(point()), []}, {"two.gpx", document(point()), []}]))
    rows("UPDATE imports SET raw_points=9,doubles=4,processed=7 WHERE id=$1", [c.import.id])
    assert {:ok, {:legacy, :multi_entry}} = run(c)

    assert [[0, 9, 4, 7]] ==
             rows("SELECT status,raw_points,doubles,processed FROM imports WHERE id=$1", [
               c.import.id
             ])

    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert [[0]] == rows("SELECT count(*) FROM notifications")
    assert_clean(c)
  end

  test "bad ZIP CRC fails before counter reset", c do
    attach(c, zipped(c, [{"ride.gpx", document(point()), [crc: 0]}]))
    rows("UPDATE imports SET raw_points=9,doubles=4 WHERE id=$1", [c.import.id])
    assert {:ok, :ok} = run(c)

    assert [[3, 9, 4]] ==
             rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    assert_clean(c)
  end

  test "verified attachment executes actual driver and completes guarded terminal callback", c do
    attach(c, document(point()))
    rows("UPDATE imports SET raw_points=9,doubles=4,processed=7 WHERE id=$1", [c.import.id])
    assert {:ok, :ok} = run(c)

    assert [[2, 1, 0, 1]] ==
             rows("SELECT status,raw_points,doubles,processed FROM imports WHERE id=$1", [
               c.import.id
             ])

    assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert_clean(c)
  end

  test "bad checksum fails before counters reset and creates localized failure", c do
    attach(c, document(point()), "AAAAAAAAAAAAAAAAAAAAAA==")
    rows("UPDATE imports SET raw_points=9,doubles=4,processed=7 WHERE id=$1", [c.import.id])
    assert {:ok, :ok} = run(c)

    assert [[3, 9, 4, 7]] ==
             rows("SELECT status,raw_points,doubles,processed FROM imports WHERE id=$1", [
               c.import.id
             ])

    assert [[title, content]] = rows("SELECT title,content FROM notifications")
    assert title =~ "fehlgeschlagen"
    assert content =~ "Checksum mismatch"
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert_clean(c)
  end

  test "missing attachment is a controlled failure", c do
    assert {:ok, :ok} = run(c)
    assert [[3]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
    assert [[1]] == rows("SELECT count(*) FROM notifications")
    assert_clean(c)
  end

  test "cloud failure never exposes a storage error or native backtrace", c do
    attach(c, document(point()), "AAAAAAAAAAAAAAAAAAAAAA==")
    assert {:ok, :ok} = run(%{c | context: %{c.context | self_hosted?: false}})
    assert [[content]] = rows("SELECT content FROM notifications")
    assert content =~ "hi@dawarich.com"
    refute content =~ "Checksum"
    refute content =~ "gpx_lifecycle"
    assert_clean(c)
  end

  for {name, sql, id} <- [
        {"deleting import", "UPDATE imports SET status=4 WHERE id=$1", :import},
        {"deleted user", "UPDATE users SET deleted_at=now() WHERE id=$1", :user},
        {"replaced attachment", "UPDATE active_storage_blobs SET checksum='changed' WHERE id=$1",
         :blob}
      ] do
    test "#{name} during an actual blocked download stops all later effects", c do
      bytes = document(point())
      attach(c, bytes)

      [[blob]] =
        rows(
          "SELECT blob_id FROM active_storage_attachments WHERE record_id=$1 AND record_type='Import'",
          [c.import.id]
        )

      rows("UPDATE active_storage_blobs SET service_name='s3' WHERE id=$1", [blob])
      parent = self()

      {url, server} =
        Dawarich.Test.DownloadServer.start(fn socket, _, _ ->
          send(parent, {:download_started, self()})
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
          assert_raise Dawarich.Imports.LeaseLost, fn -> run(%{c | context: context}) end
        end)

      receive do: ({:download_started, _} -> :ok)

      target =
        case unquote(id) do
          :import -> c.import.id
          :user -> c.import.user_id
          :blob -> blob
        end

      rows(unquote(sql), [target])
      send(server.pid, :release)
      Task.await(task, :infinity)
      Task.await(server, :infinity)
      assert [[0]] == rows("SELECT count(*) FROM points")
      assert [[0]] == rows("SELECT count(*) FROM notifications")
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert_clean(c)
    end
  end

  test "ownership loss after processing commits prevents points and false failure reports", c do
    attach(c, document(point()))

    rows(
      "CREATE FUNCTION public.lifecycle_owner_loss() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN IF NEW.status=1 THEN UPDATE phoenix.job_owners SET owner='sidekiq' WHERE key='command:imports.process_gpx'; END IF; RETURN NEW; END $$"
    )

    rows(
      "CREATE TRIGGER lifecycle_owner_loss AFTER UPDATE ON imports FOR EACH ROW EXECUTE FUNCTION public.lifecycle_owner_loss()"
    )

    try do
      assert_raise Dawarich.Imports.LeaseLost, fn -> run(c) end
      assert [[1]] == rows("SELECT status FROM imports WHERE id=$1", [c.import.id])
      assert [[0]] == rows("SELECT count(*) FROM points")
      assert [[0]] == rows("SELECT count(*) FROM notifications")
      refute Processed.done?(ScratchRepo, c.job.args["event_id"])
      assert_clean(c)
    after
      rows("DROP TRIGGER lifecycle_owner_loss ON imports")
      rows("DROP FUNCTION public.lifecycle_owner_loss()")
    end
  end

  test "fatal point preparation retains the preceding committed batch", c do
    points =
      Enum.map_join(1..1000, fn i ->
        point(
          "2026-01-01T#{String.pad_leading(Integer.to_string(div(i, 60)), 2, "0")}:#{String.pad_leading(Integer.to_string(rem(i, 60)), 2, "0")}:00Z"
        )
      end)

    attach(c, document(points <> point("not a date")))
    assert {:ok, :ok} = run(c)
    assert [[3, 1000]] == rows("SELECT status,raw_points FROM imports WHERE id=$1", [c.import.id])
    assert [[1000]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert_clean(c)
  end

  test "a completion callback failure leaves completed and resumes without parsing again", c do
    attach(c, document(point()))
    failing = %{c | context: %{c.context | on_terminal: fn -> raise "marker unavailable" end}}
    assert_raise RuntimeError, "marker unavailable", fn -> run(failing) end

    assert [[2, 1, 0]] ==
             rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    refute Processed.done?(ScratchRepo, c.job.args["event_id"])
    rows("UPDATE oban.oban_jobs SET attempt=2 WHERE id=$1", [c.job.id])
    assert {:ok, :ok} = run(%{c | job: %{c.job | attempt: 2}})

    assert [[2, 1, 0]] ==
             rows("SELECT status,raw_points,doubles FROM imports WHERE id=$1", [c.import.id])

    assert [[1]] == rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id])
    assert Processed.done?(ScratchRepo, c.job.args["event_id"])
    assert_clean(c)
  end
end
