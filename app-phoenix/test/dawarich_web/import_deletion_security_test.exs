defmodule DawarichWeb.ImportDeletionSecurityTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Jobs.Ownership

  for {mode, owner, layout} <-
        for(
          mode <- ["on", "off"],
          owner <- [:oban, :sidekiq],
          layout <- [:prepared_only, :distinct],
          do: {mode, owner, layout}
        ) do
    test "real destruction completes with authorized cleanup and issued links mode=#{mode} purge_owner=#{owner} layout=#{layout}" do
      Dawarich.EnhancedImportCase.with_env("DAWARICH_RAILS", unquote(mode), fn ->
        c = Dawarich.ImportLeaseFixture.create()
        rows("DELETE FROM oban.oban_jobs WHERE id=$1", [c.job.id])
        rows("UPDATE imports SET status=2 WHERE id=$1", [c.import.id])

        rows(
          "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1640995201,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
          [c.import.user_id, c.import.id]
        )

        assert rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id]) == [[1]]
        root = Path.join(System.tmp_dir!(), "rereview-delete-" <> Ecto.UUID.generate())
        File.mkdir_p!(root)
        on_exit(fn -> File.rm_rf!(root) end)
        config = %{service: "local", root: root}
        catalog = %{default: "local", services: %{"local" => config}}
        source = Dawarich.RailsBlobFixture.create!(ScratchRepo, root, "source.gpx", "<gpx/>")
        prepared = Dawarich.RailsBlobFixture.create!(ScratchRepo, root, "prepared.gpx", "<gpx/>")

        if unquote(layout) == :distinct do
          rows(
            "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'file',$2,now())",
            [c.import.id, source.id]
          )
        end

        rows(
          "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'prepared_download',$2,now())",
          [c.import.id, prepared.id]
        )

        Ownership.put!(ScratchRepo, "command:imports.destroy", :oban)
        Ownership.put!(ScratchRepo, "command:imports.prepared_download_purge", unquote(owner))

        args = %{
          "import_id" => c.import.id,
          "user_id" => c.import.user_id,
          "event_id" => Ecto.UUID.generate()
        }

        [[job_id]] =
          rows(
            "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,attempted_at) VALUES('executing','imports','Dawarich.Imports.DestroyWorker',$1,1,3,now()) RETURNING id",
            [args]
          )

        job = %Oban.Job{id: job_id, attempt: 1, args: args}
        previous = Dawarich.Repo.put_dynamic_repo(ScratchRepo)

        try do
          blob = Dawarich.Storage.Blobs.find(prepared.id)

          url =
            DawarichWeb.ActiveStorageUrls.service_url(
              config,
              blob,
              nil,
              "http://www.example.com",
              DateTime.utc_now()
            )

          token =
            url
            |> URI.parse()
            |> Map.fetch!(:path)
            |> String.split("/")
            |> Enum.at(-2)
            |> URI.decode()

          previous_jobs = Application.fetch_env!(:dawarich, :jobs_repo)
          Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

          try do
            assert :ok = Dawarich.Imports.DestroyWorker.perform(job)
          after
            Application.put_env(:dawarich, :jobs_repo, previous_jobs)
          end

          assert rows("SELECT id FROM imports WHERE id=$1", [c.import.id]) == []

          assert rows(
                   "SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
                   [c.import.id]
                 ) == []

          redirect =
            DawarichWeb.ActiveStorage.call(
              %{
                Plug.Test.conn(:get, "/rails/active_storage/blobs/redirect/x/prepared.gpx")
                | path_params: %{
                    "signed_id" => prepared.signed_id,
                    "filename" => ["prepared.gpx"]
                  }
              },
              action: :redirect,
              storage: catalog
            )

          disk =
            DawarichWeb.ActiveStorage.call(
              %{Plug.Test.conn(:get, url) | path_params: %{"encoded_key" => token}},
              action: :disk,
              storage: catalog
            )

          source_owned = unquote(mode) == "on" and unquote(owner) == :sidekiq
          assert redirect.status == if(source_owned, do: 302, else: 404)
          assert disk.status == if(source_owned, do: 200, else: 404)

          assert rows("SELECT phase FROM phoenix.import_destroy_runs WHERE import_id=$1", [
                   c.import.id
                 ]) == [["removed"]]

          assert rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id]) == [[0]]

          debt =
            rows(
              "SELECT worker,args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.PreparedDownloadPurgeWorker' ORDER BY id"
            )

          assert :ok = Dawarich.Imports.DestroyWorker.perform(job)

          assert rows(
                   "SELECT worker,args FROM oban.oban_jobs WHERE worker='Dawarich.Imports.PreparedDownloadPurgeWorker' ORDER BY id"
                 ) == debt

          if source_owned do
            assert rows(
                     "SELECT payload->>'blob_id' FROM phoenix.rails_commands WHERE kind='imports.prepared_download_purge' ORDER BY id"
                   )
                   |> List.flatten()
                   |> Enum.sort() ==
                     Enum.sort(
                       Enum.map(
                         if(unquote(layout) == :distinct,
                           do: [source.id, prepared.id],
                           else: [prepared.id]
                         ),
                         &to_string/1
                       )
                     )
          else
            assert Enum.any?(debt, fn [_worker, args] ->
                     Enum.any?(args["objects"], &(&1["key"] == blob.key))
                   end)

            previous_services = Application.get_env(:dawarich, :imports_services)
            Application.put_env(:dawarich, :imports_services, %{"local" => config})

            try do
              path = Dawarich.Storage.disk_path(root, blob.key)
              File.rm!(path)
              File.mkdir!(path)

              purge =
                Enum.find_value(debt, fn [_worker, args] ->
                  if Enum.any?(args["objects"], &(&1["key"] == blob.key)),
                    do: %Oban.Job{args: args}
                end)

              assert {:error, _} = Dawarich.Imports.PreparedDownloadPurgeWorker.perform(purge)
              assert File.dir?(path)
              File.rmdir!(path)
              File.write!(path, "<gpx/>")

              for [_worker, args] <- debt do
                assert :ok =
                         Dawarich.Imports.PreparedDownloadPurgeWorker.perform(%Oban.Job{
                           args: args
                         })

                assert :ok =
                         Dawarich.Imports.PreparedDownloadPurgeWorker.perform(%Oban.Job{
                           args: args
                         })

                for object <- args["objects"],
                    do: refute(File.exists?(Dawarich.Storage.disk_path(root, object["key"])))
              end
            after
              if previous_services,
                do: Application.put_env(:dawarich, :imports_services, previous_services),
                else: Application.delete_env(:dawarich, :imports_services)
            end
          end
        after
          Dawarich.Repo.put_dynamic_repo(previous)
        end
      end)
    end
  end

  for mode <- ["on", "off"] do
    test "ambiguous source refuses destruction before changing points or attachments mode=#{mode}" do
      Dawarich.EnhancedImportCase.with_env("DAWARICH_RAILS", unquote(mode), fn ->
        c = Dawarich.ImportLeaseFixture.create()
        rows("UPDATE imports SET status=2 WHERE id=$1", [c.import.id])

        rows(
          "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1640995201,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
          [c.import.user_id, c.import.id]
        )

        root = Path.join(System.tmp_dir!(), "ambiguous-delete-" <> Ecto.UUID.generate())
        File.mkdir_p!(root)
        on_exit(fn -> File.rm_rf!(root) end)

        for name <- ["first.gpx", "second.gpx"] do
          blob = Dawarich.RailsBlobFixture.create!(ScratchRepo, root, name, "<gpx/>")

          rows(
            "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'file',$2,now())",
            [c.import.id, blob.id]
          )
        end

        Ownership.put!(ScratchRepo, "command:imports.destroy", :oban)
        Ownership.put!(ScratchRepo, "command:imports.prepared_download_purge", :oban)

        args = %{
          "import_id" => c.import.id,
          "user_id" => c.import.user_id,
          "event_id" => Ecto.UUID.generate()
        }

        [[id]] =
          rows(
            "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts,attempted_at) VALUES('executing','imports','Dawarich.Imports.DestroyWorker',$1,1,3,now()) RETURNING id",
            [args]
          )

        previous = Application.fetch_env!(:dawarich, :jobs_repo)
        Application.put_env(:dawarich, :jobs_repo, ScratchRepo)

        try do
          assert_raise ArgumentError, "Ambiguous import source attachment", fn ->
            Dawarich.Imports.DestroyWorker.perform(%Oban.Job{id: id, attempt: 1, args: args})
          end

          assert rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id]) == [[1]]

          assert rows(
                   "SELECT count(*) FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
                   [c.import.id]
                 ) == [[2]]

          assert rows("SELECT status FROM imports WHERE id=$1", [c.import.id]) == [[2]]

          assert rows("SELECT count(*) FROM phoenix.import_destroy_runs WHERE import_id=$1", [
                   c.import.id
                 ]) == [[0]]
        after
          Application.put_env(:dawarich, :jobs_repo, previous)
        end
      end)
    end
  end
end
