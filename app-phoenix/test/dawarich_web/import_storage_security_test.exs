defmodule DawarichWeb.ImportStorageSecurityTest do
  use Dawarich.IngestCase, async: false

  test "deleting an import revokes its prepared blob capability immediately" do
    user = Dawarich.Test.RailsUser.insert!(%{id: 872_004, email: "owner@posthoc.test"})
    root = Path.join(System.tmp_dir!(), "posthoc-link-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    config = %{service: "local", root: root}
    catalog = %{default: "local", services: %{"local" => config}}
    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.prepared_download_purge", :oban)

    for mode <- ["on", "off"] do
      Dawarich.EnhancedImportCase.with_env("DAWARICH_RAILS", mode, fn ->
        ref = Dawarich.RailsBlobFixture.create!(Repo, root, "prepared.gpx", "<gpx/>")

        [[id]] =
          Repo.query!(
            "INSERT INTO imports(user_id,name,source,status,additional_data_extraction_status,created_at,updated_at) VALUES($1,'prepared.gpx',4,2,3,now(),now()) RETURNING id",
            [user.id],
            log: false
          ).rows

        Repo.query!(
          "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'prepared_download',$2,now())",
          [id, ref.id],
          log: false
        )

        blob = Dawarich.Storage.Blobs.find(ref.id)

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

        assert {:ok, _} =
                 Repo.transaction(fn ->
                   Dawarich.Imports.ImportBlobPurges.enqueue!(Repo, id, user.id, ref.id, ref.id)

                   Repo.query!(
                     "DELETE FROM active_storage_attachments WHERE record_id=$1 AND record_type='Import'",
                     [id],
                     log: false
                   )

                   Repo.query!("DELETE FROM imports WHERE id=$1", [id], log: false)
                 end)

        conn = Plug.Test.conn(:get, "/rails/active_storage/blobs/redirect/ignored/prepared.gpx")

        response =
          DawarichWeb.ActiveStorage.call(
            %{
              conn
              | path_params: %{"signed_id" => ref.signed_id, "filename" => ["prepared.gpx"]}
            },
            action: :redirect,
            storage: catalog
          )

        assert response.status == 404

        disk =
          DawarichWeb.ActiveStorage.call(
            %{Plug.Test.conn(:get, url) | path_params: %{"encoded_key" => token}},
            action: :disk,
            storage: catalog
          )

        assert disk.status == 404
        assert File.exists?(Dawarich.Storage.disk_path(root, blob.key))

        assert [[1]] =
                 Repo.query!(
                   "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Imports.PreparedDownloadPurgeWorker' AND args->'objects' @> $1::jsonb",
                   [[%{"key" => blob.key, "service_name" => "local"}]],
                   log: false
                 ).rows
      end)
    end
  end

  import Plug.Conn
  alias Dawarich.{Storage, Repo}
  alias DawarichWeb.ActiveStorage
  alias Dawarich.Test.RailsUser

  setup do
    root = Path.join(System.tmp_dir!(), "posthoc-storage-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{
      root: root,
      config: %{service: "local", root: root},
      catalog: %{default: "local", services: %{"local" => %{service: "local", root: root}}}
    }
  end

  defp put(c, url, bytes) do
    token =
      url |> URI.parse() |> Map.fetch!(:path) |> String.split("/") |> List.last() |> URI.decode()

    conn =
      Plug.Test.conn(:put, url, bytes)
      |> put_req_header("content-type", "application/gpx+xml")
      |> put_req_header("content-length", Integer.to_string(byte_size(bytes)))

    ActiveStorage.call(%{conn | path_params: %{"encoded_token" => token}},
      action: :disk_update,
      storage: c.catalog
    )
  end

  defp create(c, user, bytes) do
    session = RailsUser.session(user.id)

    conn =
      Plug.Test.conn(:post, "http://www.example.com/rails/active_storage/direct_uploads", %{
        "blob" => %{
          "filename" => "private.gpx",
          "byte_size" => byte_size(bytes),
          "checksum" => Base.encode64(:crypto.hash(:md5, bytes)),
          "content_type" => "application/gpx+xml"
        }
      })
      |> assign(:rails_session, session)
      |> assign(:current_user, user)
      |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))

    response = ActiveStorage.call(conn, action: :direct_upload, storage: c.catalog)
    assert response.status == 200
    Jason.decode!(response.resp_body)
  end

  defp purge!(c, blob, user) do
    {:ok, id} = Dawarich.RailsMessages.verified_blob_id(blob["signed_id"], DateTime.utc_now())

    [[import_id]] =
      Repo.query!(
        "INSERT INTO imports(user_id,name,source,created_at,updated_at) VALUES($1,'purged.gpx',4,now(),now()) RETURNING id",
        [user.id],
        log: false
      ).rows

    Repo.query!(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES('Import',$1,'file',$2,now())",
      [import_id, id],
      log: false
    )

    {:ok, :ok} =
      Repo.transaction(fn ->
        Dawarich.Imports.ImportBlobPurges.authorize!(Repo, import_id, user.id, id, id)
        Repo.query!("DELETE FROM active_storage_attachments WHERE blob_id=$1", [id], log: false)
        :ok
      end)

    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.prepared_download_purge", :oban)

    args = %{
      "blob_id" => id,
      "import_id" => import_id,
      "user_id" => user.id,
      "source_blob_id" => id,
      "event_id" => Ecto.UUID.generate()
    }

    [[job_id]] =
      Repo.query!(
        "INSERT INTO oban.oban_jobs(state,queue,worker,args,attempt,max_attempts) VALUES('executing','imports','Dawarich.Imports.ImportBlobPurgeWorker',$1,1,3) RETURNING id",
        [args],
        log: false
      ).rows

    previous = Application.fetch_env(:dawarich, :imports_services)
    Application.put_env(:dawarich, :imports_services, c.catalog.services)

    try do
      assert :ok =
               Dawarich.Imports.ImportBlobPurgeWorker.run(Repo, %Oban.Job{
                 id: job_id,
                 attempt: 1,
                 args: args
               })
    after
      case previous do
        {:ok, value} -> Application.put_env(:dawarich, :imports_services, value)
        :error -> Application.delete_env(:dawarich, :imports_services)
      end
    end

    assert Repo.query!("SELECT id FROM active_storage_blobs WHERE id=$1", [id], log: false).rows ==
             []

    refute File.exists?(Storage.disk_path(c.root, blob["key"]))
  end

  test "a successful purge cannot be undone with the old upload capability", c do
    user = RailsUser.insert!(%{id: 872_005, email: "purge@posthoc.test"})
    bytes = "<gpx/>"
    blob = create(c, user, bytes)
    assert put(c, blob["direct_upload"]["url"], bytes).status == 204
    purge!(c, blob, user)
    assert put(c, blob["direct_upload"]["url"], bytes).status == 404
    refute File.exists?(Storage.disk_path(c.root, blob["key"]))
  end

  test "purge between upload staging and publication prevents object resurrection", c do
    user = RailsUser.insert!(%{id: 872_006, email: "overlap@posthoc.test"})
    bytes = "<gpx/>"
    blob = create(c, user, bytes)
    url = blob["direct_upload"]["url"]

    token =
      url |> URI.parse() |> Map.fetch!(:path) |> String.split("/") |> List.last() |> URI.decode()

    conn =
      Plug.Test.conn(:put, url, bytes)
      |> put_req_header("content-type", "application/gpx+xml")
      |> put_req_header("content-length", Integer.to_string(byte_size(bytes)))

    response =
      ActiveStorage.call(%{conn | path_params: %{"encoded_token" => token}},
        action: :disk_update,
        storage: c.catalog,
        before_publish: fn -> purge!(c, blob, user) end
      )

    assert response.status == 404
    refute File.exists?(Storage.disk_path(c.root, blob["key"]))
    assert Path.wildcard(Path.join(c.root, ".phoenix-tmp/*")) == []
  end

  test "guest upload receipts cannot be claimed by an authenticated user", c do
    user = RailsUser.insert!(%{id: 872_007, email: "guest-claim@posthoc.test"})
    session = Map.take(RailsUser.session(user.id), ["_csrf_token"])
    bytes = "<gpx/>"

    params = %{
      "blob" => %{
        "filename" => "guest.gpx",
        "byte_size" => byte_size(bytes),
        "checksum" => Base.encode64(:crypto.hash(:md5, bytes)),
        "content_type" => "application/gpx+xml"
      }
    }

    conn =
      Plug.Test.conn(:post, "http://www.example.com/rails/active_storage/direct_uploads", params)
      |> assign(:rails_session, session)
      |> assign(:current_user, nil)
      |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))

    response = ActiveStorage.call(conn, action: :direct_upload, storage: c.catalog)
    assert response.status == 200
    blob = Jason.decode!(response.resp_body)
    assert put(c, blob["direct_upload"]["url"], bytes).status == 204

    assert {:error, :forbidden} =
             Dawarich.Imports.UploadCreate.create(Repo, user, [blob["signed_id"]], %{
               storage: c.config,
               self_hosted?: true
             })
  end

  test "another user cannot claim an upload created in the victim session", c do
    victim = RailsUser.insert!(%{id: 872_001, email: "victim@posthoc.test"})
    attacker = RailsUser.insert!(%{id: 872_002, email: "attacker@posthoc.test"})
    bytes = "<gpx><wpt lat=\"51\" lon=\"12\"><name>Private waypoint</name></wpt></gpx>"
    blob = create(c, victim, bytes)
    assert put(c, blob["direct_upload"]["url"], bytes).status == 204
    Dawarich.Jobs.Ownership.put!(Repo, "command:imports.process_gpx", :oban)

    result =
      Dawarich.Imports.UploadCreate.create(Repo, attacker, [blob["signed_id"]], %{
        storage: c.config,
        self_hosted?: true
      })

    assert {:error, :forbidden} = result

    assert {:ok, [id]} =
             Dawarich.Imports.UploadCreate.create(Repo, victim, [blob["signed_id"]], %{
               storage: c.config,
               self_hosted?: true
             })

    assert {:ok, ^bytes} =
             Dawarich.Imports.Download.with_file(
               Repo,
               victim.id,
               id,
               %{services: c.catalog.services},
               fn path, _, _ -> File.read!(path) end
             )
  end
end
