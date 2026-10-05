defmodule Dawarich.Points.DeviceTagBackfillTest do
  use Dawarich.JobsCase
  import ExUnit.CaptureLog

  alias Dawarich.RecalculationFixtures, as: Fixtures
  alias Dawarich.Points.DeviceTagBackfill
  alias Dawarich.Storage.S3
  alias Dawarich.Test.{DownloadServer, RawHTTP}

  @source Path.expand("../../fixtures/a12d1b3/Records.json", __DIR__)
  @key "a12d1b3-records-source"

  setup do
    source = Fixtures.case!("tracker_records")
    Fixtures.load!(ScratchRepo, source)
    dir = Path.join(System.tmp_dir!(), "device-tag-backfill-#{Ecto.UUID.generate()}")
    File.mkdir_p!(Path.join([dir, "storage", "a1", "2d"]))
    File.mkdir_p!(Path.join(dir, "tmp"))
    File.cp!(@source, Path.join([dir, "storage", "a1", "2d", @key]))
    on_exit(fn -> File.rm_rf!(dir) end)

    opts = [
      services: %{
        "test" => %{service: "local", stored_service: "test", root: Path.join(dir, "storage")}
      },
      download_opts: [temp_dir: Path.join(dir, "tmp")],
      zone: "Europe/Berlin",
      now: ~U[2026-10-03 12:00:00Z]
    ]

    %{dir: dir, opts: opts, source: source}
  end

  test "reads the attached blob service and only updates candidate points in its user/import",
       c do
    user =
      hd(c.source["input"]["users"])
      |> Map.merge(%{"id" => 170_102, "email" => "foreign@example.invalid"})

    Fixtures.row!(ScratchRepo, "users", user)
    import = hd(c.source["input"]["imports"]) |> Map.put("id", 170_802)
    Fixtures.row!(ScratchRepo, "imports", import)
    point = Enum.at(c.source["input"]["points"], 5)

    Fixtures.row!(
      ScratchRepo,
      "points",
      Map.merge(point, %{"id" => 190_001, "user_id" => 170_102})
    )

    Fixtures.row!(
      ScratchRepo,
      "points",
      Map.merge(point, %{"id" => 190_002, "import_id" => 170_802, "lonlat" => nil})
    )

    Fixtures.row!(
      ScratchRepo,
      "points",
      Map.merge(point, %{"id" => 190_003, "tracker_id" => "real", "lonlat" => nil})
    )

    preserved = rows("SELECT id,tracker_id,updated_at FROM points WHERE id>=190001 ORDER BY id")
    assert DeviceTagBackfill.run(ScratchRepo, 170_801, c.opts) == 3

    assert rows(
             "SELECT id,tracker_id FROM points WHERE import_id=170801 AND id<190001 ORDER BY id"
           ) ==
             [
               [170_203, "google-records-device-11"],
               [170_204, "google-records-device-22"],
               [170_205, "legacy-import-170801"],
               [170_206, "google-records-device-55"]
             ]

    assert rows("SELECT id,tracker_id,updated_at FROM points WHERE id>=190001 ORDER BY id") ==
             preserved

    assert rows(
             "SELECT count(*) FROM points WHERE tracker_id LIKE 'google-records-device-%' AND updated_at>'2026-10-03 12:00:00'"
           ) == [[3]]

    assert File.ls!(Path.join(c.dir, "tmp")) == []
    assert DeviceTagBackfill.run(ScratchRepo, 170_801, c.opts) == 0

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, c.source)
    bytes = File.read!(@source)

    {url, server} =
      DownloadServer.start(fn socket, _, _ ->
        RawHTTP.reply(
          socket,
          "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(bytes)}\r\nConnection: close\r\n\r\n" <>
            bytes
        )
      end)

    aws =
      S3.config!(%{
        "AWS_ACCESS_KEY_ID" => "AKIA_SYNTHETIC",
        "AWS_SECRET_ACCESS_KEY" => "synthetic-secret",
        "AWS_REGION" => "eu-central-1",
        "AWS_BUCKET" => "dawarich",
        "AWS_ENDPOINT_URL" => url
      })

    config = Map.merge(aws, %{service: "s3", stored_service: "historic_s3"})
    rows("UPDATE active_storage_blobs SET service_name='historic_s3'")

    assert DeviceTagBackfill.run(
             ScratchRepo,
             170_801,
             Keyword.put(c.opts, :services, %{"historic_s3" => config})
           ) == 3

    Task.await(server)
    assert File.ls!(Path.join(c.dir, "tmp")) == []
  end

  test "unreadable or absent uploads return zero and remove verified temporary files", c do
    original = rows("SELECT id,tracker_id FROM points ORDER BY id")
    assert DeviceTagBackfill.run(ScratchRepo, -1, c.opts) == 0
    assert DeviceTagBackfill.run(ScratchRepo, 170_801, Keyword.put(c.opts, :services, %{})) == 0
    path = Path.join([c.dir, "storage", "a1", "2d", @key])
    File.write!(path, "sensitive-source-bytes")
    log = capture_log(fn -> assert DeviceTagBackfill.run(ScratchRepo, 170_801, c.opts) == 0 end)
    refute log =~ "sensitive-source-bytes"
    assert File.ls!(Path.join(c.dir, "tmp")) == []
    bytes = "{broken-source"
    File.write!(path, bytes)

    rows("UPDATE active_storage_blobs SET byte_size=$1,checksum=$2", [
      byte_size(bytes),
      Base.encode64(:crypto.hash(:md5, bytes))
    ])

    assert DeviceTagBackfill.run(ScratchRepo, 170_801, c.opts) == 0
    assert File.ls!(Path.join(c.dir, "tmp")) == []
    assert rows("SELECT id,tracker_id FROM points ORDER BY id") == original

    reset!(ScratchRepo)
    Fixtures.load!(ScratchRepo, c.source)
    File.cp!(@source, path)
    parent = self()
    pool = ScratchRepo.get_dynamic_repo()

    {pid, ref} =
      spawn_monitor(fn ->
        ScratchRepo.put_dynamic_repo(pool)

        DeviceTagBackfill.run(
          ScratchRepo,
          170_801,
          Keyword.put(c.opts, :after_verified, fn retained ->
            send(parent, {:retained, retained})
            receive do: (:finish -> :ok)
          end)
        )
      end)

    on_exit(fn -> Process.exit(pid, :kill) end)

    retained =
      receive do
        {:retained, retained} -> retained
        {:DOWN, ^ref, :process, ^pid, reason} -> flunk("caller exited: #{inspect(reason)}")
      end

    assert File.exists?(retained)
    {:monitored_by, watchers} = Process.info(pid, :monitored_by)
    guards = for guard <- watchers -- [self()], do: {guard, Process.monitor(guard)}
    assert guards != []
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

    for {guard, guard_ref} <- guards do
      assert_receive {:DOWN, ^guard_ref, :process, ^guard, reason}
      assert reason in [:normal, :noproc]
    end

    refute File.exists?(retained)
    assert File.ls!(Path.join(c.dir, "tmp")) == []
    rows("DELETE FROM active_storage_attachments")
    assert DeviceTagBackfill.run(ScratchRepo, 170_801, c.opts) == 0
  end
end
