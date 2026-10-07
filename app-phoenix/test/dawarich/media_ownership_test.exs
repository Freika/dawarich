defmodule Dawarich.MediaOwnershipTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.{Repo, RailsMessages, Storage}
  alias Dawarich.RouteVideos.{Writes, AnalysisWorker}
  alias Dawarich.Posters.Command
  @now ~U[2026-10-07 10:00:00Z]

  setup context do
    Ecto.Migrator.run(Repo, Path.expand("priv/repo/oban_migrations"), :up,
      all: true,
      prefix: "oban",
      log: false
    )

    Dawarich.MigrationModules.purge()
    repo = if context[:scratch], do: Dawarich.ScratchRepo, else: Repo
    Dawarich.JobsCase.reset!(repo)
    old = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", context.mode)
    Dawarich.Jobs.Ownership.put!(repo, "cron:route_videos_purge_job", :oban)

    root = Path.join(System.tmp_dir!(), "posthoc-media-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    on_exit(fn ->
      if old, do: System.put_env("DAWARICH_RAILS", old), else: System.delete_env("DAWARICH_RAILS")
      File.rm_rf!(root)
    end)

    repo.query!(
      "INSERT INTO users(id,email,created_at,updated_at) VALUES(1,'owner@example.test',now(),now()),(2,'other@example.test',now(),now())",
      [],
      log: false
    )

    %{
      repo: repo,
      mode: context.mode,
      root: root,
      services: %{default: "local", services: %{"local" => %{service: "local", root: root}}}
    }
  end

  for mode <- ["on", "off"] do
    @tag mode: mode
    test "F1 #{mode} refuses another owner blob at adoption", c do
      {blob, _} = blob!(c, "{\"identified\":true,\"analyzed\":true}")
      assert {:ok, %{id: _}} = create(blob, 1)
      result = create(blob, 2)
      IO.puts("F1 observed cross_owner_adoption=#{inspect(result)}")
      assert match?({:error, _}, result)
      assert {:ok, %{id: _}} = create(blob, 1)

      for {table, type} <- [{"posters", "Poster"}, {"imports", "Import"}, {"exports", "Export"}] do
        [[record]] =
          Repo.query!(
            "INSERT INTO #{table}(user_id,name,status,created_at,updated_at) VALUES(1,'Synthetic',0,now(),now()) RETURNING id",
            [],
            log: false
          ).rows

        {foreign, _} = blob!(c, "{}")

        Repo.query!(
          "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file',$1,$2,$3,now())",
          [type, record, foreign],
          log: false
        )

        assert {:error, %{phase: :invalid_signature}} = create(foreign, 2)

        assert Repo.query!(
                 "SELECT blob_id FROM active_storage_attachments WHERE blob_id=$1",
                 [foreign],
                 log: false
               ).rows == [[foreign]]
      end

      assert Repo.query!("SELECT id FROM phoenix.rails_commands", [], log: false).rows == []
    end

    @tag mode: mode
    test "F2 #{mode} legacy poster purge immediately revokes parent and variants", c do
      {blob, key} = blob!(c, "{}")

      Repo.transaction(fn ->
        Command.purge(Repo, if(c.mode == "off", do: :sidekiq, else: :oban), %{
          "poster_id" => 123,
          "user_id" => 1,
          "blob_ids" => [blob]
        })
      end)

      [[worker]] = Repo.query!("SELECT worker FROM oban.oban_jobs", [], log: false).rows
      response = disk(key, c)
      IO.puts("F2 observed worker=#{worker} disk_before_worker=#{response.status}")
      assert response.status == 404
      {legacy, legacy_key} = blob!(c, "{}")
      {child, child_key} = blob!(c, "{}")

      [[variant]] =
        Repo.query!(
          "INSERT INTO active_storage_variant_records(blob_id,variation_digest) VALUES($1,$2) RETURNING id",
          [legacy, Ecto.UUID.generate()],
          log: false
        ).rows

      Repo.query!(
        "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('image','ActiveStorage::VariantRecord',$1,$2,now())",
        [variant, child],
        log: false
      )

      args = %{"poster_id" => 123, "blob_ids" => [legacy], "event_id" => Ecto.UUID.generate()}
      path = Storage.disk_path(c.root, legacy_key)
      File.rm!(path)
      File.mkdir!(path)

      assert {:error, {:storage_delete, _}} =
               Dawarich.Posters.PurgeWorker.run(Repo, args, services: c.services)

      assert disk(legacy_key, c).status == 404
      assert disk(child_key, c).status == 404
      refute Dawarich.Jobs.Processed.done?(Repo, args["event_id"])
      File.rmdir!(path)
      File.write!(path, "synthetic")
      assert :ok = Dawarich.Posters.PurgeWorker.run(Repo, args, services: c.services)
      assert :ok = Dawarich.Posters.PurgeWorker.run(Repo, args, services: c.services)
      assert Dawarich.Jobs.Processed.done?(Repo, args["event_id"])
      refute File.exists?(Storage.disk_path(c.root, child_key))
    end

    @tag mode: mode, scratch: true
    test "F3 #{mode} concurrent redelivery probes video exactly once", c do
      {blob, key} = blob!(c, "{}")
      assert {:ok, %{id: _}} = create(blob, 1, c.repo)

      [[args]] =
        c.repo.query!(
          "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.RouteVideos.AnalysisWorker'",
          [],
          log: false
        ).rows

      path = Storage.disk_path(c.root, key)
      File.rm!(path)

      assert_raise File.CopyError, fn ->
        AnalysisWorker.run(c.repo, args, services: c.services)
      end

      refute Dawarich.Jobs.Processed.done?(c.repo, args["event_id"])
      File.write!(path, "synthetic")

      probe = Path.join(c.root, "probe")
      release = Path.join(c.root, "release")

      File.write!(
        probe,
        "#!/bin/sh\ntouch '#{c.root}/started_'$$\ni=0\nwhile [ ! -f '#{release}' ] && [ $i -lt 200 ]; do sleep 0.05; i=$((i+1)); done\nprintf '%s' '{\"streams\":[{\"codec_type\":\"video\",\"width\":16,\"height\":9}],\"format\":{}}'\n"
      )

      File.chmod!(probe, 0o700)

      tasks =
        for delivery <- [args, args, Map.put(args, "event_id", Ecto.UUID.generate())],
            do:
              Task.async(fn ->
                AnalysisWorker.run(c.repo, delivery, services: c.services, ffprobe: probe)
              end)

      observed = wait_count(c.root, 2, 20)
      File.write!(release, "go")
      results = Enum.map(tasks, &Task.await(&1, 15_000))
      IO.puts("F3 observed ffprobe_invocations=#{observed} results=#{inspect(results)}")
      assert observed == 1
    end

    @tag mode: mode
    test "F4 #{mode} committed revocation defeats an earlier attachment admission", c do
      repo = Dawarich.ScratchRepo
      Dawarich.JobsCase.reset!(repo)
      Dawarich.Jobs.Ownership.put!(repo, "cron:route_videos_purge_job", :oban)

      repo.query!(
        "INSERT INTO users(id,email,created_at,updated_at) VALUES(1,'owner@example.test',now(),now())",
        [],
        log: false
      )

      key = Storage.generate_key()

      [[blob]] =
        repo.query!(
          "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,'synthetic.mp4','video/mp4',$2,'local',9,'synthetic',now()) RETURNING id",
          [key, "{\"identified\":true,\"analyzed\":true}"],
          log: false
        ).rows

      path = Storage.disk_path(c.root, key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "synthetic")

      params = %{
        "route_video" => %{
          "file" => RailsMessages.blob_id(blob),
          "name" => "Synthetic",
          "settings" => %{}
        }
      }

      create = fn -> Writes.create(repo, %{id: 1}, params, @now, "en", %{max_per_user: 0}) end
      assert {:ok, %{id: first}} = create.()
      parent = self()
      handler = "media-admission-" <> Ecto.UUID.generate()
      on_exit(fn -> :telemetry.detach(handler) end)

      :telemetry.attach(
        handler,
        [:dawarich, :scratch_repo, :query],
        fn _, _, meta, _ ->
          if Process.get(:posthoc_pause) == true and
               String.starts_with?(meta.query, "SELECT content_type,byte_size,metadata") and
               not String.contains?(meta.query, "FOR UPDATE") do
            send(parent, {:admitted, self()})

            receive do
              :proceed -> :ok
            after
              5_000 -> raise "probe synchronization timeout"
            end
          end
        end,
        nil
      )

      task =
        Task.async(fn ->
          Process.put(:posthoc_pause, true)
          create.()
        end)

      assert_receive {:admitted, pid}, 5_000
      assert {:ok, ^first} = Writes.destroy(repo, 1, first, @now)

      [[metadata]] =
        repo.query!("SELECT metadata FROM active_storage_blobs WHERE id=$1", [blob], log: false).rows

      assert Dawarich.Storage.NativePurge.pending?(metadata)
      send(pid, :proceed)
      result = Task.await(task, 10_000)
      :telemetry.detach(handler)

      [[args]] =
        repo.query!(
          "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker'",
          [],
          log: false
        ).rows

      assert :ok = Dawarich.Exports.PurgeWorker.run(args, repo: repo, services: c.services)
      assert match?({:error, _}, result)

      assert repo.query!("SELECT id FROM active_storage_blobs WHERE id=$1", [blob], log: false).rows ==
               []

      refute File.exists?(path)
    end
  end

  defp wait_count(root, target, left) do
    count = length(Path.wildcard(Path.join(root, "started_*")))

    if count >= target or left == 0 do
      count
    else
      Process.sleep(50)
      wait_count(root, target, left - 1)
    end
  end

  defp create(blob, user, repo \\ Repo),
    do:
      Writes.create(
        repo,
        %{id: user},
        %{
          "route_video" => %{
            "file" => RailsMessages.blob_id(blob),
            "name" => "Synthetic",
            "settings" => %{}
          }
        },
        @now,
        "en",
        %{max_per_user: 0}
      )

  defp blob!(c, metadata) do
    key = Storage.generate_key()

    [[id]] =
      c.repo.query!(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,'synthetic.mp4','video/mp4',$2,'local',9,'synthetic',now()) RETURNING id",
        [key, metadata],
        log: false
      ).rows

    path = Storage.disk_path(c.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "synthetic")
    {id, key}
  end

  defp disk(key, c) do
    token =
      RailsMessages.sign_storage(
        %{"key" => key, "content_type" => "video/mp4", "service_name" => "local"},
        "blob_key",
        DateTime.add(@now, 300)
      )

    Plug.Test.conn(:get, "/rails/active_storage/disk/token/synthetic.mp4")
    |> Map.put(:path_params, %{"encoded_key" => token, "filename" => ["synthetic.mp4"]})
    |> DawarichWeb.ActiveStorage.call(action: :disk, storage: c.services, now: @now)
  end
end
