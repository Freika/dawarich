defmodule Dawarich.UploadCleanupRaceTest do
  use Dawarich.DataCase, async: true
  import Plug.Conn
  alias Dawarich.{Storage, Uploads}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Uploads.CleanupWorker

  setup do
    user = Dawarich.Test.RailsUser.insert!(%{id: 13121, email: "cleanup-race@example.invalid"})
    root = Path.join(System.tmp_dir!(), "cleanup-race-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    local = %{service: "local", root: root}
    %{scope: Scope.for_user(user, "en"), local: local, root: root}
  end

  test "an admitted PUT cannot publish after upload cancellation", c do
    {ref, blob, _path} = reserve(c, c.local)

    result =
      put(c, blob, fn ->
        assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref)
      end)

    assert result.status == 404
    refute File.exists?(Storage.disk_path(c.root, blob.key))
  end

  test "cleanup fences the row before object deletion while an admitted PUT resumes", c do
    {ref, blob, path} = reserve(c, c.local)
    parent = self()

    task =
      Task.async(fn ->
        receive do
          :start -> :ok
        end

        put(c, blob, fn ->
          send(parent, {:admitted, self()})

          receive do
            :publish -> :ok
          after
            5000 -> raise "publication barrier timed out"
          end
        end)
      end)

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), task.pid)
    send(task.pid, :start)
    on_exit(fn -> if Process.alive?(task.pid), do: Task.shutdown(task, :brutal_kill) end)
    assert_receive {:admitted, pid}, 1000
    assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref)
    expire(ref)

    adapter =
      s3(c, "local", fn :delete, _url, _body ->
        refute Repo.in_transaction?()
        File.rm(path)
        send(pid, :publish)
        assert Task.await(task).status == 404
        assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
        {:ok, %{status_code: 204, headers: [], body: ""}}
      end)

    assert :ok =
             CleanupWorker.run(%{"reference" => ref}, repo: Repo, services: %{"local" => adapter})

    refute File.exists?(path)
  end

  test "remote cleanup identity survives blob removal and sweeps late in-flight arrivals", c do
    objects = start_supervised!({Agent, fn -> %{} end})

    adapter =
      s3(c, "s3", fn :delete, url, _body ->
        refute Repo.in_transaction?()
        key = url |> URI.parse() |> Map.fetch!(:path) |> Path.basename()
        Agent.update(objects, &Map.delete(&1, key))
        {:ok, %{status_code: 204, headers: [], body: ""}}
      end)

    {ref, blob, _path} = reserve(c, adapter)
    Agent.update(objects, &Map.put(&1, blob.key, "original"))
    assert {:ok, :cancelled} = Uploads.cancel(c.scope, ref)
    expire(ref)
    opts = [repo: Repo, services: %{"s3" => adapter}]
    assert :ok = CleanupWorker.run(%{"reference" => ref}, opts)
    assert [] == rows("SELECT id FROM active_storage_blobs WHERE id=$1", [blob.id])
    Agent.update(objects, &Map.put(&1, blob.key, "late in-flight arrival"))
    assert :ok = CleanupWorker.run(%{"reference" => ref}, opts)
    assert %{} == Agent.get(objects, & &1)

    Agent.update(objects, &Map.put(&1, blob.key, "later arrival"))

    rows(
      "UPDATE phoenix.native_uploads SET cleanup_at=timezone('UTC',now())-interval '1 second' WHERE reference=$1",
      [ref]
    )

    rows(
      "UPDATE oban.oban_jobs SET state='completed' WHERE worker='Dawarich.Uploads.CleanupWorker' AND args->>'reference'=$1",
      [ref]
    )

    [[before]] =
      rows(
        "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.CleanupWorker' AND args->>'reference'=$1",
        [ref]
      )

    assert {:ok, 0} = Uploads.sweep(repo: Repo)

    assert [[after_count]] =
             rows(
               "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.CleanupWorker' AND args->>'reference'=$1",
               [ref]
             )

    assert after_count == before + 1

    assert [[args]] =
             rows(
               "SELECT args FROM oban.oban_jobs WHERE worker='Dawarich.Uploads.CleanupWorker' AND args->>'reference'=$1 ORDER BY id DESC LIMIT 1",
               [ref]
             )

    assert :ok = CleanupWorker.run(args, opts)
    assert %{} == Agent.get(objects, & &1)

    assert [["purged", blob.key, "s3"]] ==
             rows(
               "SELECT state,object_key,service_name FROM phoenix.native_uploads WHERE reference=$1",
               [ref]
             )
  end

  defp reserve(c, storage) do
    bytes = "<gpx/>"

    attrs = %{
      filename: "race.gpx",
      byte_size: byte_size(bytes),
      checksum: Base.encode64(:crypto.hash(:md5, bytes)),
      content_type: "application/gpx+xml"
    }

    assert {:ok, ref} =
             Uploads.reserve(c.scope, attrs, %{repo: Repo, storage: storage, kind: :imports})

    [[id]] = rows("SELECT blob_id FROM phoenix.native_uploads WHERE reference=$1", [ref])
    blob = Storage.Blobs.find(id)
    {ref, blob, Storage.disk_path(c.root, blob.key)}
  end

  defp expire(ref),
    do:
      rows(
        "UPDATE phoenix.native_uploads SET target_until=timezone('UTC',now())-interval '1 second' WHERE reference=$1",
        [ref]
      )

  defp put(c, blob, barrier) do
    {url, _} =
      DawarichWeb.ActiveStorageUrls.direct_upload(
        c.local,
        blob,
        "http://www.example.com",
        DateTime.utc_now()
      )

    token =
      url |> URI.parse() |> Map.fetch!(:path) |> String.split("/") |> List.last() |> URI.decode()

    conn =
      Plug.Test.conn(:put, url, "<gpx/>")
      |> put_req_header("content-type", blob.content_type)
      |> put_req_header("content-length", "6")

    DawarichWeb.ActiveStorage.call(%{conn | path_params: %{"encoded_token" => token}},
      action: :disk_update,
      storage: %{default: "local", services: %{"local" => c.local}},
      before_publish: barrier
    )
  end

  defp s3(c, stored, respond) do
    config =
      Storage.S3.config!(%{
        "AWS_ACCESS_KEY_ID" => "synthetic",
        "AWS_SECRET_ACCESS_KEY" => "synthetic",
        "AWS_REGION" => "eu-central-1",
        "AWS_BUCKET" => "synthetic"
      })

    config
    |> Map.merge(%{service: "s3", root: c.root, stored_service: stored})
    |> Map.update!(
      :ex_aws,
      &Keyword.merge(&1,
        http_client: Dawarich.Test.UploadCleanupHttp,
        http_opts: [respond: respond]
      )
    )
  end
end
