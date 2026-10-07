defmodule Dawarich.A12f3bE13SharedPurgeTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.{ScratchRepo, Storage}
  alias Dawarich.Jobs.{Drain, Ownership}
  alias Dawarich.Exports.PurgeWorker

  setup do
    root = Path.join(System.tmp_dir!(), "shared-purge-" <> Ecto.UUID.generate())
    previous = Application.fetch_env!(:dawarich, :rails_root)
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS STORAGE_BACKEND))
    Application.put_env(:dawarich, :rails_root, root)
    System.delete_env("STORAGE_BACKEND")
    start_oban(__MODULE__)

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_root, previous)

      for key <- ~w(DAWARICH_RAILS STORAGE_BACKEND) do
        if env[key], do: System.put_env(key, env[key]), else: System.delete_env(key)
      end

      File.rm_rf!(root)
    end)

    %{root: root}
  end

  @tag a12f3b_case: "F2"
  test "F2 every shared native producer retains blob and variant rows through storage failure and serialized retry",
       c do
    for mode <- [:standalone, :coexistence],
        path <- [:poster, :reject, :failed_save, :destroy, :retention, :export],
        mode == :standalone or path != :export do
      if mode == :standalone,
        do: System.put_env("DAWARICH_RAILS", "off"),
        else: System.delete_env("DAWARICH_RAILS")

      owner = if mode == :standalone, do: :sidekiq, else: :oban
      Ownership.put!(ScratchRepo, "command:posters.create", owner, pinned: true)
      Ownership.put!(ScratchRepo, "cron:route_videos_purge_job", owner, pinned: true)

      [[user]] =
        rows(
          "INSERT INTO users(email,created_at,updated_at) VALUES($1,now(),now()) RETURNING id",
          [Ecto.UUID.generate() <> "@purge.test"]
        )

      {blob, file} = blob!(c.root, if(path == :reject, do: "text/plain", else: "video/mp4"))
      {child, child_file} = blob!(c.root, "image/png")

      [[variant]] =
        rows(
          "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,$2) RETURNING id",
          [blob, Ecto.UUID.generate()]
        )

      attach!("ActiveStorage::VariantRecord", variant, child)
      assert {:ok, _} = ScratchRepo.transaction(fn -> produce(path, user, blob) end)

      [[job_id, args]] =
        rows(
          "SELECT id,args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker' ORDER BY id DESC LIMIT 1"
        )

      retained!(blob, child, variant)
      assert File.exists?(file) and File.exists?(child_file)
      assert rows("SELECT kind FROM phoenix.rails_commands") == []

      assert_raise KeyError, fn ->
        PurgeWorker.run(args, services: %{services: %{}})
      end

      retained!(blob, child, variant)
      File.rm!(file)
      File.mkdir!(file)
      assert %{success: 0, failure: 1} = Oban.drain_queue(__MODULE__, queue: :exports)
      retained!(blob, child, variant)

      assert [["retryable", 1, 1]] =
               rows("SELECT state,attempt,cardinality(errors) FROM oban.oban_jobs WHERE id=$1", [
                 job_id
               ])

      assert Drain.status(ScratchRepo).counts.incomplete_oban == 1

      assert %{success: 0, failure: 1} =
               Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

      retained!(blob, child, variant)
      File.rmdir!(file)
      File.write!(file, "synthetic media")
      File.rm!(child_file)
      File.mkdir!(child_file)

      assert %{success: 0, failure: 1} =
               Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

      retained!(blob, child, variant)
      refute File.exists?(file)
      assert File.exists?(child_file)

      assert %{success: 0, failure: 1} =
               Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

      File.rmdir!(child_file)
      File.write!(child_file, "synthetic variant")

      assert %{success: 1, failure: 0} =
               Oban.drain_queue(__MODULE__, queue: :exports, with_scheduled: true)

      refute File.exists?(file) or File.exists?(child_file)
      assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1)", [[blob, child]]) == []
      assert rows("SELECT id FROM active_storage_variant_records WHERE id=$1", [variant]) == []

      assert rows(
               "SELECT blob_id FROM active_storage_attachments WHERE record_id=$1 AND record_type='ActiveStorage::VariantRecord'",
               [variant]
             ) == []

      assert :ok = PurgeWorker.perform(%Oban.Job{args: Jason.decode!(Jason.encode!(args))})
      assert Drain.status(ScratchRepo).counts.incomplete_oban == 0
    end
  end

  defp retained!(blob, child, variant) do
    assert rows("SELECT id FROM active_storage_blobs WHERE id=ANY($1) ORDER BY id", [
             [blob, child]
           ]) == Enum.map(Enum.sort([blob, child]), &[&1])

    assert rows("SELECT id FROM active_storage_variant_records WHERE id=$1", [variant]) == [
             [variant]
           ]

    assert rows(
             "SELECT blob_id FROM active_storage_attachments WHERE record_id=$1 AND record_type='ActiveStorage::VariantRecord'",
             [variant]
           ) == [[child]]
  end

  defp produce(:poster, user, blob) do
    [[id]] =
      rows(
        "INSERT INTO posters(name,status,settings,user_id,created_at,updated_at) VALUES('synthetic',0,'{}',$1,now(),now()) RETURNING id",
        [user]
      )

    attach!("Poster", id, blob)
    Dawarich.Posters.Persistence.delete(id, %{id: user}, ScratchRepo)
  end

  defp produce(:export, user, blob) do
    [[id]] =
      rows(
        "INSERT INTO exports(name,user_id,created_at,updated_at) VALUES('synthetic',$1,now(),now()) RETURNING id",
        [user]
      )

    attach!("Export", id, blob)
    Dawarich.Exports.Delete.call(ScratchRepo, user, id)
  end

  defp produce(:reject, user, blob),
    do:
      Dawarich.RouteVideos.Writes.create(
        ScratchRepo,
        %{id: user},
        %{"route_video" => %{"file" => Dawarich.RailsMessages.blob_id(blob)}},
        DateTime.utc_now(),
        "en",
        %{max_per_user: 0}
      )

  defp produce(:failed_save, user, blob),
    do: Dawarich.RouteVideos.AttachmentEffects.cleanup_failed_save!(ScratchRepo, user, blob)

  defp produce(path, user, blob) do
    [[id]] =
      rows(
        "INSERT INTO route_videos(name,user_id,status,settings,created_at,updated_at) VALUES('synthetic',$1,0,'{}',now(),now()) RETURNING id",
        [user]
      )

    attach!("RouteVideo", id, blob)

    if path == :destroy,
      do: Dawarich.RouteVideos.Writes.destroy(ScratchRepo, user, id, DateTime.utc_now()),
      else: Dawarich.RouteVideos.Retention.expire(ScratchRepo, id, DateTime.utc_now())
  end

  defp attach!(type, id, blob),
    do:
      rows(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file',$1,$2,$3,now())",
        [type, id, blob]
      )

  defp blob!(root, type) do
    key = Storage.generate_key()

    [[id]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,created_at) VALUES($1,'synthetic',$2,'{\"identified\":true,\"analyzed\":true}','local',15,now()) RETURNING id",
        [key, type]
      )

    file = Storage.disk_path(Path.join(root, "storage"), key)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, "synthetic media")
    {id, file}
  end
end
