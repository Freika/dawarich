defmodule Dawarich.ClaimedUploadCleanupTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Imports, Storage, Uploads}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Uploads.CleanupWorker

  setup do
    user = Dawarich.Test.RailsUser.insert!(%{id: 13221, email: "claimed-debt@example.invalid"})
    root = Path.join(System.tmp_dir!(), "claimed-debt-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    local = %{service: "local", stored_service: "s3", root: root}
    objects = start_supervised!({Agent, fn -> %{} end})

    remote =
      Storage.S3.config!(%{
        "AWS_ACCESS_KEY_ID" => "synthetic",
        "AWS_SECRET_ACCESS_KEY" => "synthetic",
        "AWS_REGION" => "eu-central-1",
        "AWS_BUCKET" => "synthetic"
      })
      |> Map.merge(%{service: "s3", root: root})
      |> Map.update!(:ex_aws, fn aws ->
        Keyword.merge(aws,
          http_client: Dawarich.Test.UploadCleanupHttp,
          http_opts: [
            respond: fn :delete, url, _ ->
              refute Repo.in_transaction?()
              key = url |> URI.parse() |> Map.fetch!(:path) |> Path.basename()
              assert [] == rows("SELECT id FROM active_storage_blobs WHERE key=$1", [key])
              Agent.update(objects, &Map.delete(&1, key))
              {:ok, %{status_code: 204, headers: [], body: ""}}
            end
          ]
        )
      end)

    for command <-
          ~w(imports.process_gpx imports.destroy imports.prepared_download_purge users.destroy),
        do: Dawarich.Jobs.Ownership.put!(Repo, "command:" <> command, :oban)

    %{scope: Scope.for_user(user, "en"), local: local, remote: remote, objects: objects}
  end

  test "claimed remote import deletion retains debt for replay and in-flight arrivals", c do
    {ref, blob, id} = claimed_import(c)
    assert {:ok, :queued} = Imports.delete(c.scope, id, repo: Repo)

    [[event]] =
      rows(
        "SELECT event_id::text FROM job_outbox WHERE command_type='imports.destroy' AND aggregate_id=$1",
        [id]
      )

    args = %{"import_id" => id, "user_id" => c.scope.user.id, "event_id" => event}
    job = Repo.insert!(Dawarich.Imports.DestroyWorker.new(args), prefix: "oban")
    rows("UPDATE oban.oban_jobs SET state='executing',attempt=1 WHERE id=$1", [job.id])

    assert {:ok, :ok} =
             Dawarich.Imports.DestroyLease.with_import(
               Repo,
               %{job | attempt: 1},
               &Dawarich.Imports.DestroyService.call/1
             )

    assert [] == rows("SELECT id FROM imports WHERE id=$1", [id])

    assert [["cancelled"]] ==
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [ref])

    purge(c, "Dawarich.Imports.PreparedDownloadPurgeWorker")
    assert_debt_and_arrivals(c, ref, blob)
  end

  test "claimed remote account destruction retains debt after owner removal", c do
    {ref, blob, _id} = claimed_import(c)
    rows("UPDATE users SET deleted_at=now() WHERE id=$1", [c.scope.user.id])

    assert :ok =
             Dawarich.Users.DestroyWorker.run(Repo, %{
               "user_id" => c.scope.user.id,
               "event_id" => Ecto.UUID.generate()
             })

    assert [] == rows("SELECT id FROM users WHERE id=$1", [c.scope.user.id])

    assert [["cancelled"]] ==
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [ref])

    purge(c, "Dawarich.Exports.PurgeWorker")
    assert_debt_and_arrivals(c, ref, blob)
  end

  test "shared claimed upload stays attached and creates no deletion debt", c do
    {ref, blob, id} = claimed_import(c)

    rows(
      "INSERT INTO active_storage_attachments(name,record_type,record_id,blob_id,created_at) VALUES('file','Export',999,$1,now())",
      [blob.id]
    )

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               assert [{_, _, _}] = Dawarich.Imports.ImportBlobPurges.removals!(Repo, id)

               assert [{:skip, :shared}] =
                        Dawarich.Imports.ImportBlobPurges.enqueue_many!(
                          Repo,
                          id,
                          c.scope.user.id,
                          Dawarich.Imports.ImportBlobPurges.removals!(Repo, id)
                        )

               rows(
                 "DELETE FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1",
                 [id]
               )

               Dawarich.Exports.PurgeWorker.enqueue!(Repo, [blob.id])
             end)

    assert [["claimed", nil]] ==
             rows("SELECT state,cleanup_at FROM phoenix.native_uploads WHERE reference=$1", [ref])

    assert [[1]] == rows("SELECT count(*) FROM active_storage_blobs WHERE id=$1", [blob.id])

    assert [] ==
             rows("SELECT id FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.CleanupWorker'")

    assert Map.has_key?(Agent.get(c.objects, & &1), blob.key)
  end

  defp claimed_import(c) do
    bytes = "<gpx/>"

    attrs = %{
      filename: "claimed.gpx",
      byte_size: byte_size(bytes),
      checksum: Base.encode64(:crypto.hash(:md5, bytes)),
      content_type: "application/gpx+xml"
    }

    assert {:ok, ref} =
             Uploads.reserve(c.scope, attrs, %{repo: Repo, storage: c.local, kind: :imports})

    [[blob_id]] = rows("SELECT blob_id FROM phoenix.native_uploads WHERE reference=$1", [ref])
    blob = Storage.Blobs.find(blob_id)
    path = Storage.disk_path(c.local.root, blob.key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, bytes)
    Agent.update(c.objects, &Map.put(&1, blob.key, bytes))

    assert {:ok, grant} =
             Uploads.target(c.scope, ref, %{}, repo: Repo, services: %{"s3" => c.remote})

    {target, _headers} =
      DawarichWeb.ActiveStorageUrls.direct_upload(
        grant.storage,
        grant.blob,
        "http://www.example.com",
        grant.issued_at
      )

    assert URI.parse(target).query =~ "X-Amz-Signature"
    assert {:ok, [id]} = Imports.create(c.scope, [ref], repo: Repo, services: %{"s3" => c.local})

    assert [["claimed"]] ==
             rows("SELECT state FROM phoenix.native_uploads WHERE reference=$1", [ref])

    {ref, blob, id}
  end

  defp purge(c, worker) do
    [[args]] =
      rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 ORDER BY id DESC LIMIT 1", [worker])

    assert :ok =
             Dawarich.Exports.PurgeWorker.run(args,
               repo: Repo,
               resolve_service: fn _ -> {:ok, c.remote} end
             )

    assert %{} == Agent.get(c.objects, & &1)
  end

  defp assert_debt_and_arrivals(c, ref, blob) do
    assert [[state, key, service, until, cleanup_at]] =
             rows(
               "SELECT state,object_key,service_name,target_until,cleanup_at FROM phoenix.native_uploads WHERE reference=$1",
               [ref]
             )

    assert state in ["cancelled", "purged"]
    assert {key, service} == {blob.key, "s3"}
    assert NaiveDateTime.compare(cleanup_at, until) == :gt
    Agent.update(c.objects, &Map.put(&1, blob.key, "replayed still-valid PUT"))
    opts = [repo: Repo, services: %{"s3" => c.remote}]
    assert {:snooze, seconds} = CleanupWorker.run(%{"reference" => ref}, opts)
    assert seconds > 0

    rows(
      "UPDATE phoenix.native_uploads SET target_until=timezone('UTC',now())-interval '1 second' WHERE reference=$1",
      [ref]
    )

    assert :ok = CleanupWorker.run(%{"reference" => ref}, opts)
    assert %{} == Agent.get(c.objects, & &1)
    Agent.update(c.objects, &Map.put(&1, blob.key, "in-flight PUT completed after expiry"))

    rows(
      "UPDATE oban.oban_jobs SET state='completed' WHERE worker='Dawarich.Uploads.CleanupWorker' AND args->>'reference'=$1",
      [ref]
    )

    rows(
      "UPDATE phoenix.native_uploads SET cleanup_at=timezone('UTC',now())-interval '1 second' WHERE reference=$1",
      [ref]
    )

    assert {:ok, 0} = Uploads.sweep(repo: Repo)

    [[args]] =
      rows(
        "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.CleanupWorker' AND args->>'reference'=$1 ORDER BY id DESC LIMIT 1",
        [ref]
      )

    assert :ok = CleanupWorker.run(args, opts)
    assert %{} == Agent.get(c.objects, & &1)
    assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
  end
end
