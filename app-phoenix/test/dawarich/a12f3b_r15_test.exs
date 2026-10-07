defmodule Dawarich.A12f3bR15Test do
  use Dawarich.IngestCase, async: false
  alias Dawarich.{RailsMessages, Repo, Storage}
  alias Dawarich.Jobs.{Dispatch, Ownership}
  alias Dawarich.Posters.{Command, Generation, Persistence}
  alias Dawarich.RouteVideos.Writes
  alias Dawarich.Exports.PurgeWorker

  @now ~U[2026-10-06 10:00:00Z]

  setup do
    Ecto.Migrator.run(Repo, Path.expand("../../priv/repo/oban_migrations", __DIR__), :up,
      all: true,
      prefix: "oban",
      log: false
    )

    Dawarich.MigrationModules.purge()
    Dawarich.JobsCase.reset!(Repo)
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")
    root = Path.join(System.tmp_dir!(), "r15-#{System.unique_integer([:positive])}")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")

      File.rm_rf!(root)
    end)

    rows(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(1,'r15@example.test',now(),now())"
    )

    %{
      root: root,
      services: %{default: "local", services: %{"local" => %{service: "local", root: root}}}
    }
  end

  @tag a12f3b_case: "R15k01"
  test "posters.created native producer reaches its source terminal effect" do
    Ownership.put!(Repo, "command:posters.create", :sidekiq, pinned: true)
    assert {:ok, id} = Persistence.create(%{}, %{id: 1}, "de", Repo)
    assert [[payload]] = rows("SELECT payload FROM public.job_outbox")
    assert payload == %{"poster_id" => id, "user_id" => 1, "locale" => "de"}
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    Command.produce(Repo, :sidekiq, id, %{id: 1}, "de", NaiveDateTime.utc_now())
    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]

    start_supervised!(
      {Oban,
       name: :r15_creation,
       repo: Repo,
       prefix: "oban",
       notifier: Oban.Notifiers.PG,
       testing: :manual}
    )

    assert %{dispatched: 1} = Dispatch.run(repo: Repo, oban: :r15_creation)

    [[args]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Posters.CreateWorker'")

    assert :ok = Generation.run(id, 1, args["event_id"], "de", repo: Repo)
    assert :ok = Generation.run(id, 1, args["event_id"], "de", repo: Repo)
    assert rows("SELECT status FROM posters WHERE id=$1", [id]) == [[3]]
    Command.produce(Repo, :sidekiq, id, %{id: 1}, "de", NaiveDateTime.utc_now())
    assert rows("SELECT count(*) FROM public.job_outbox") == [[1]]
    System.delete_env("DAWARICH_RAILS")
    assert {:ok, _} = Persistence.create(%{}, %{id: 1}, "en", Repo)
    assert rows("SELECT kind FROM phoenix.rails_commands") == [["posters.created"]]
  end

  @tag a12f3b_case: "R15k03"
  test "posters.purge native producer reaches its source terminal effect", c do
    Ownership.put!(Repo, "command:posters.create", :sidekiq, pinned: true)
    assert {:ok, id} = Persistence.create(%{}, %{id: 1}, "en", Repo)
    {blob, path} = blob!(c, "image/png")
    attach!("Poster", id, blob)
    assert {:ok, ^id} = Persistence.delete(id, %{id: 1}, Repo)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == [[blob]]
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    assert [args] = purges()
    assert {:error, {:storage_delete, _reason}} = fail_delete(c, args, path)
    assert :ok = PurgeWorker.run(args, services: c.services, repo: Repo)
    assert :ok = PurgeWorker.run(args, services: c.services, repo: Repo)
    refute File.exists?(path)
    assert {:error, :missing} = Persistence.delete(id, %{id: 1}, Repo)
    System.delete_env("DAWARICH_RAILS")
    assert {:ok, other} = Persistence.create(%{}, %{id: 1}, "en", Repo)
    {shared, shared_path} = blob!(c, "image/png")
    attach!("Poster", other, shared)
    assert {:ok, ^other} = Persistence.delete(other, %{id: 1}, Repo)

    assert rows("SELECT kind FROM phoenix.rails_commands ORDER BY id") == [
             ["posters.created"],
             ["posters.purge"]
           ]

    assert File.exists?(shared_path)
    Ownership.put!(Repo, "command:posters.create", :oban)
    assert {:ok, native} = Persistence.create(%{}, %{id: 1}, "en", Repo)
    {native_blob, native_path} = blob!(c, "image/png")
    attach!("Poster", native, native_blob)
    assert {:ok, ^native} = Persistence.delete(native, %{id: 1}, Repo)

    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [native_blob]) == [
             [native_blob]
           ]

    inaccessible!(native_blob, c)
    native_purge = List.last(purges())
    assert {:error, {:storage_delete, _reason}} = fail_delete(c, native_purge, native_path)
    assert :ok = PurgeWorker.run(native_purge, services: c.services, repo: Repo)
    refute File.exists?(native_path)
  end

  @tag a12f3b_case: "R15k04"
  test "route_videos.attachment_job native producer reaches its source terminal effect", c do
    Ownership.put!(Repo, "cron:route_videos_purge_job", :sidekiq, pinned: true)
    {rejected, rejected_path} = blob!(c, "text/plain")
    assert {:error, %{phase: :rejected}} = create(rejected)
    inaccessible!(rejected, c)
    assert [{args, path}] = Enum.zip(purges(), [rejected_path])
    assert {:error, {:storage_delete, _reason}} = fail_delete(c, args, path)
    assert :ok = PurgeWorker.run(args, services: c.services, repo: Repo)
    assert :ok = PurgeWorker.run(args, services: c.services, repo: Repo)
    refute File.exists?(path)
    assert {:error, %{phase: :invalid_signature}} = create(rejected)
    {blob, path} = blob!(c, "video/mp4")
    assert {:ok, %{id: first}} = create(blob)
    assert {:ok, %{id: second}} = create(blob)
    assert {:ok, ^first} = Writes.destroy(Repo, 1, first, @now)
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob]) == [[blob]]
    assert File.exists?(path)
    assert {:ok, ^second} = Writes.destroy(Repo, 1, second, @now)
    inaccessible!(blob, c)
    assert length(purges()) == 2
    assert :ok = PurgeWorker.run(List.last(purges()), services: c.services, repo: Repo)
    refute File.exists?(path)
    assert {:error, :not_found} = Writes.destroy(Repo, 1, second, @now)
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    {guarded, guarded_path} = blob!(c, "video/mp4")
    assert {:ok, %{id: guarded_video}} = create(guarded)

    [[attachment_id]] =
      rows("SELECT id FROM active_storage_attachments WHERE blob_id=$1", [guarded])

    payload = %{
      "user_id" => 1,
      "blob_id" => guarded,
      "action" => "purge_detached",
      "attachment" => %{
        "id" => attachment_id,
        "blob_id" => guarded,
        "record_id" => guarded_video,
        "name" => "file",
        "record_type" => "RouteVideo"
      }
    }

    enqueue = fn p ->
      Repo.transaction(fn -> Dawarich.RouteVideos.AttachmentJob.enqueue!(Repo, p) end)
    end

    assert {:ok, :ok} = enqueue.(payload)
    rows("DELETE FROM active_storage_attachments WHERE id=$1", [attachment_id])

    for invalid <- [
          Map.put(payload, "user_id", 2),
          Map.put(payload, "action", "unknown"),
          put_in(payload, ["attachment", "blob_id"], guarded + 1),
          put_in(payload, ["attachment", "name"], "image")
        ] do
      assert {:ok, :ok} = enqueue.(invalid)
      assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [guarded]) == [[guarded]]
    end

    assert {:ok, :ok} = enqueue.(payload)
    assert {:ok, :ok} = enqueue.(payload)
    assert length(purges()) == 3
    assert :ok = PurgeWorker.run(List.last(purges()), services: c.services, repo: Repo)
    refute File.exists?(guarded_path)
    assert rows("SELECT kind FROM phoenix.rails_commands") == []
    {unidentified, _} = blob!(c, "video/mp4")
    rows("UPDATE active_storage_blobs SET metadata='{}' WHERE id=$1", [unidentified])
    assert {:ok, %{id: uploaded}} = create(unidentified)

    [[analysis]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.RouteVideos.AnalysisWorker'")

    probe = Path.join(c.root, "ffprobe")

    File.write!(
      probe,
      "#!/bin/sh\ncat <<'JSON'\n{\"streams\":[{\"codec_type\":\"video\",\"width\":1920,\"height\":1080,\"duration\":\"2.5\",\"display_aspect_ratio\":\"16:9\"}],\"format\":{}}\nJSON\n"
    )

    File.chmod!(probe, 0o700)

    assert :ok =
             apply(Dawarich.RouteVideos.AnalysisWorker, :run, [
               Repo,
               analysis,
               [services: c.services, ffprobe: probe]
             ])

    assert :ok =
             apply(Dawarich.RouteVideos.AnalysisWorker, :run, [
               Repo,
               analysis,
               [services: c.services, ffprobe: probe]
             ])

    [[metadata]] = rows("SELECT metadata FROM active_storage_blobs WHERE id=$1", [unidentified])

    assert Jason.decode!(metadata) == %{
             "identified" => true,
             "analyzed" => true,
             "width" => 1920.0,
             "height" => 1080.0,
             "duration" => 2.5,
             "audio" => false,
             "video" => true,
             "display_aspect_ratio" => [16, 9]
           }

    assert {:ok, ^uploaded} = Writes.destroy(Repo, 1, uploaded, @now)
    inaccessible!(unidentified, c)

    assert :ok =
             apply(Dawarich.RouteVideos.AnalysisWorker, :run, [
               Repo,
               analysis,
               [services: c.services, ffprobe: probe]
             ])

    assert :ok = PurgeWorker.run(List.last(purges()), services: c.services, repo: Repo)
    System.delete_env("DAWARICH_RAILS")
    {legacy, _} = blob!(c, "text/plain")
    assert {:error, %{phase: :rejected}} = create(legacy)
    assert rows("SELECT kind FROM phoenix.rails_commands") == [["route_videos.attachment_job"]]
    Ownership.put!(Repo, "cron:route_videos_purge_job", :oban)
    {native, native_path} = blob!(c, "text/plain")
    assert {:error, %{phase: :rejected}} = create(native)
    inaccessible!(native, c)
    assert :ok = PurgeWorker.run(List.last(purges()), services: c.services, repo: Repo)
    refute File.exists?(native_path)
  end

  defp create(blob),
    do:
      Writes.create(
        Repo,
        %{id: 1},
        %{"route_video" => %{"file" => RailsMessages.blob_id(blob)}},
        @now,
        "en",
        %{max_per_user: 0}
      )

  defp purges,
    do:
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker' ORDER BY id"
      )
      |> List.flatten()

  defp fail_delete(c, args, path) do
    File.rm!(path)
    File.mkdir!(path)
    result = PurgeWorker.run(args, services: c.services, repo: Repo)
    File.rmdir!(path)
    File.write!(path, "synthetic")
    result
  end

  defp blob!(c, type) do
    key = Storage.generate_key()

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,'media.mp4',$2,$3,'local',9,'synthetic',now()) RETURNING id",
        [key, type, ~s({"identified":true,"analyzed":true})]
      )

    path = Storage.disk_path(c.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "synthetic")

    signed =
      RailsMessages.sign_storage(
        %{"key" => key, "content_type" => type, "service_name" => "local"},
        "blob_key",
        DateTime.add(@now, 300)
      )

    Process.put({:disk_token, id}, signed)
    assert download(id, c).status == 200
    {id, path}
  end

  defp attach!(type, id, blob),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file',$1,$2,$3,now())",
        [type, id, blob]
      )

  defp rows(sql, params \\ []), do: Repo.query!(sql, params, log: false).rows

  defp download(id, c) do
    Plug.Test.conn(:get, "/rails/active_storage/disk/token/media.mp4")
    |> Map.put(:path_params, %{
      "encoded_key" => Process.get({:disk_token, id}),
      "filename" => "media.mp4"
    })
    |> DawarichWeb.ActiveStorage.call(action: :disk, now: @now, storage: c.services)
  end

  defp inaccessible!(id, c) do
    assert rows("SELECT id FROM active_storage_blobs WHERE id=$1", [id]) == [[id]]
    assert download(id, c).status == 404

    conn =
      Plug.Test.conn(:get, "/rails/active_storage/blobs/redirect/x/media.mp4")
      |> Map.put(:path_params, %{
        "signed_id" => RailsMessages.blob_id(id),
        "filename" => ["media.mp4"]
      })

    assert DawarichWeb.ActiveStorage.call(conn, action: :redirect, now: @now, storage: c.services).status ==
             404
  end
end
