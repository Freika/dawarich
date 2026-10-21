defmodule DawarichWeb.NativeUploadTargetTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  require Logger
  import ExUnit.CaptureLog
  alias Dawarich.{Accounts, Repo, Uploads}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    prior = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if prior,
        do: System.put_env("DAWARICH_RAILS", prior),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    RailsUser.insert!(%{id: 16832, email: "target@example.invalid"})
    RailsUser.insert!(%{id: 16833, email: "foreign-target@example.invalid"})
    scope = Scope.for_user(Accounts.get(16832), "en")

    attrs = %{
      filename: "backup.zip",
      byte_size: 3,
      checksum: Base.encode64(:crypto.hash(:md5, "zip")),
      content_type: "application/zip"
    }

    {:ok, ref} = Uploads.reserve(scope, attrs, %{kind: :imports})
    %{scope: scope, ref: ref}
  end

  defp request(user, ref, opts \\ []) do
    session = RailsUser.session(user)
    token = DawarichWeb.RailsCsrf.masked_token(session)

    conn =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("sec-fetch-site", Keyword.get(opts, :site, "same-origin"))
      |> put_req_header("x-csrf-token", Keyword.get(opts, :csrf, token))

    post(
      conn,
      "/native/uploads/target",
      Keyword.get(opts, :body, Jason.encode!(%{"upload_ref" => ref}))
    )
  end

  test "external upload metadata and crashed handlers contain no target capability" do
    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        current_user: Accounts.get(16832),
        locale: "en",
        base_url: "http://www.example.com",
        checksums: %{"0" => Base.encode64(:crypto.hash(:md5, "zip"))}
      }
    }

    entry = %Phoenix.LiveView.UploadEntry{
      client_name: "backup.zip",
      client_size: 3,
      client_type: "application/zip",
      ref: "0"
    }

    assert {:ok, meta, returned} = DawarichWeb.DirectUpload.presign(entry, socket)
    assert Enum.sort(Map.keys(meta)) == [:upload_ref, :uploader]
    assert is_binary(Map.fetch!(meta, :upload_ref))
    refute Map.has_key?(returned.assigns, :signed_id)

    log =
      capture_log(fn ->
        Logger.error(fn ->
          [
            "upload crashed ",
            inspect(%{
              upload_ref: Map.fetch!(meta, :upload_ref),
              url: "target-capability",
              signed_id: "blob-capability",
              checksum: "digest"
            })
          ]
        end)
      end)

    refute log =~ "target-capability"
    refute log =~ "blob-capability"
  end

  test "target requests refuse stale sessions foreign refs and oversized bodies before storage writes",
       c do
    good = request(16832, c.ref)
    assert good.status == 200
    assert get_resp_header(good, "cache-control") == ["no-store"]

    assert %{"url" => url, "headers" => %{"Content-Type" => "application/zip"}} =
             Jason.decode!(good.resp_body)

    assert url =~ "/rails/active_storage/disk/"
    assert request(16833, c.ref).status == 404
    assert request(16832, c.ref, csrf: "invalid").status == 403
    assert request(16832, c.ref, site: "cross-site").status == 403
    assert request(16832, c.ref, body: String.duplicate("x", 4097)).status == 413
    Repo.query!("UPDATE users SET encrypted_password='rotated' WHERE id=16832", [], log: false)
    assert request(16832, c.ref).status in [401, 403]
    assert [[1]] = Repo.query!("SELECT count(*) FROM active_storage_blobs", [], log: false).rows
  end

  test "cleanup deadline covers every target even after signing is delayed", c do
    issued = DateTime.add(DateTime.utc_now(), -60)
    assert {:ok, grant} = Uploads.target(c.scope, c.ref, %{}, clock: fn -> issued end)
    assert Map.fetch!(grant, :issued_at) == issued
    response = apply(DawarichWeb.NativeUploadTarget, :response, [grant, "http://www.example.com"])

    token =
      response.url
      |> URI.parse()
      |> Map.fetch!(:path)
      |> String.split("/")
      |> List.last()
      |> URI.decode()

    [[deadline]] =
      Repo.query!("SELECT target_until FROM phoenix.native_uploads WHERE reference=$1", [c.ref],
        log: false
      ).rows

    assert {:ok, _} =
             Dawarich.RailsMessages.verify_storage(token, "blob_token", DateTime.add(issued, 299))

    assert :error =
             Dawarich.RailsMessages.verify_storage(
               token,
               "blob_token",
               DateTime.from_naive!(NaiveDateTime.add(deadline, 1), "Etc/UTC")
             )
  end

  test "storage request path logs never retain a signed upload capability" do
    log =
      capture_log(fn ->
        Logger.error(fn ->
          ["PUT /rails/active_storage/disk/", "synthetic-private-disk-capability"]
        end)

        Logger.error(fn ->
          Jason.encode!(%{
            request_path:
              "/rails/active_storage/blobs/redirect/synthetic-private-blob-capability/private.zip"
          })
        end)

        Logger.flush()
      end)

    assert log =~ "PUT /rails/active_storage/disk/"
    refute log =~ "synthetic-private-disk-capability"
    refute log =~ "synthetic-private-blob-capability"
    refute log =~ "private.zip"
  end
end
