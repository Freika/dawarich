defmodule DawarichWeb.ZipDeletionSecurityTest do
  use Dawarich.JobsCase, async: false
  alias Dawarich.Imports.{ImportState, Lease, ProcessWorker, ZipFanout}
  alias Dawarich.Test.NormalFormats

  setup do
    Dawarich.Test.NormalWholeEffects.record_order!(ScratchRepo)
    on_exit(fn -> Dawarich.Test.NormalWholeEffects.remove_order!(ScratchRepo) end)
    root = Path.join(System.tmp_dir!(), "zip-fanout-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  for mode <- ["on", "off"], owner <- [:oban, :sidekiq], prepared? <- [false, true] do
    @tag fix3_case: "zip-#{mode}-#{owner}-#{prepared?}"
    test "native ZIP removal authorizes every owned attachment before revoking mode=#{mode} owner=#{owner} prepared=#{prepared?}",
         c do
      Dawarich.EnhancedImportCase.with_env("DAWARICH_RAILS", unquote(mode), fn ->
        c = fixture(c, "unsupported_single")
        Dawarich.Jobs.Ownership.put!(ScratchRepo, "command:imports.process_normal", :oban)

        Dawarich.Jobs.Ownership.put!(
          ScratchRepo,
          "command:imports.prepared_download_purge",
          unquote(owner)
        )

        if unquote(prepared?) do
          for name <- ["prepared_download", "derived_zip_member"] do
            b = Dawarich.RailsBlobFixture.create!(ScratchRepo, c.root, name <> ".gpx", "<gpx/>")

            rows(
              "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,$2,$3,now())",
              [c.import.id, name, b.id]
            )
          end
        end

        previous = Dawarich.Repo.put_dynamic_repo(ScratchRepo)

        try do
          links =
            for [id] <-
                  rows(
                    "SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
                    [c.import.id]
                  ) do
              blob = Dawarich.Storage.Blobs.find(id)

              {blob,
               DawarichWeb.ActiveStorageUrls.service_url(
                 %{service: "local", root: c.root},
                 blob,
                 nil,
                 "http://www.example.com",
                 DateTime.utc_now()
               )}
            end

          rows(
            "INSERT INTO points(user_id,import_id,timestamp,lonlat,created_at,updated_at) VALUES($1,$2,1640995201,ST_SetSRID(ST_MakePoint(10,50),4326)::geography,now(),now())",
            [c.import.user_id, c.import.id]
          )

          result = run(c)
          assert {:ok, :removed} = result
          assert rows("SELECT id FROM imports WHERE id=$1", [c.import.id]) == []

          assert rows(
                   "SELECT id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
                   [c.import.id]
                 ) == []

          assert rows("SELECT count(*) FROM points WHERE import_id=$1", [c.import.id]) == [[0]]

          assert rows(
                   "SELECT phase FROM phoenix.import_archive_children WHERE parent_id=$1 AND entry_name=''",
                   [c.import.id]
                 ) == [["removed"]]

          for {blob, url} <- links do
            assert File.exists?(Dawarich.Storage.disk_path(c.root, blob.key))
            assert_links_revoked(blob, url, c.root)

            if unquote(mode) == "on" and unquote(owner) == :sidekiq do
              assert rows("SELECT key,service_name FROM active_storage_blobs WHERE id=$1", [
                       blob.id
                     ]) ==
                       [[blob.key, blob.service_name]]

              assert rows(
                       "SELECT blob_id FROM phoenix.import_blob_purges WHERE blob_id=$1 AND import_id=$2 AND user_id=$3",
                       [blob.id, c.import.id, c.import.user_id]
                     ) == [[blob.id]]

              assert [[true]] =
                       rows(
                         "SELECT EXISTS(SELECT 1 FROM phoenix.rails_commands WHERE kind='imports.prepared_download_purge' AND payload->>'blob_id'=$1)",
                         [to_string(blob.id)]
                       )
            else
              assert [[true]] =
                       rows(
                         "SELECT EXISTS(SELECT 1 FROM oban.oban_jobs WHERE worker='Dawarich.Imports.PreparedDownloadPurgeWorker' AND args->'objects' @> $1::jsonb)",
                         [[%{"key" => blob.key, "service_name" => blob.service_name}]]
                       )
            end
          end

          debt = rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
          jobs = rows("SELECT worker,args FROM oban.oban_jobs ORDER BY id")
          assert :ok = ProcessWorker.perform(c.job)
          assert rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id") == debt
          assert rows("SELECT worker,args FROM oban.oban_jobs ORDER BY id") == jobs
        after
          Dawarich.Repo.put_dynamic_repo(previous)
        end
      end)
    end
  end

  defp assert_links_revoked(blob, url, root) do
    catalog = %{default: "local", services: %{"local" => %{service: "local", root: root}}}

    redirect =
      DawarichWeb.ActiveStorage.call(
        %{
          Plug.Test.conn(:get, "/rails/active_storage/blobs/redirect/x/file")
          | path_params: %{
              "signed_id" => Dawarich.RailsMessages.blob_id(blob.id),
              "filename" => [blob.filename]
            }
        },
        action: :redirect,
        storage: catalog
      )

    token =
      url |> URI.parse() |> Map.fetch!(:path) |> String.split("/") |> Enum.at(-2) |> URI.decode()

    disk =
      DawarichWeb.ActiveStorage.call(
        %{Plug.Test.conn(:get, url) | path_params: %{"encoded_key" => token}},
        action: :disk,
        storage: catalog
      )

    assert redirect.status == 404
    assert disk.status == 404
  end

  defp fixture(c, name), do: Map.merge(c, NormalFormats.whole!(name, ScratchRepo, c.root))

  defp run(c) do
    Lease.with_import(
      ScratchRepo,
      c.job,
      c.import,
      fn lease ->
        ImportState.with_snapshot(lease, fn state ->
          path = Dawarich.Storage.disk_path(c.root, state.blob.key)
          ZipFanout.call(lease, path, c.context)
        end)
      end,
      Keyword.put(
        ProcessWorker.lease_options(),
        :lane,
        Map.get(c, :lane, "command:imports.process_normal")
      )
    )
  end
end
