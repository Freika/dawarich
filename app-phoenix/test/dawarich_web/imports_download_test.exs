defmodule DawarichWeb.ImportsDownloadTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]
  alias Dawarich.Test.RailsUser
  alias Dawarich.Imports.UploadCreate
  alias Dawarich.Jobs.Ownership
  @endpoint DawarichWeb.Endpoint
  defmodule PreparingRepo do
    def transaction(fun), do: Dawarich.Repo.transaction(fun)

    def query!(sql, params \\ [], opts \\ []) do
      if String.starts_with?(sql, "SELECT i.name") and String.ends_with?(sql, "FOR SHARE OF i,u") do
        if preparation = Process.delete(:g44_download_preparation) do
          {user, id, context} = preparation

          [[source]] =
            Dawarich.Repo.query!(
              "SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='file'",
              [id]
            ).rows

          :ok = Dawarich.Imports.Download.prepare!(Dawarich.Repo, user, id, source, context)
        end
      end

      Dawarich.Repo.query!(sql, params, opts)
    end
  end

  setup do
    user = RailsUser.insert!(%{id: 7597, email: "native-download-http@example.test"})

    Repo.query!(
      File.read!(
        Path.expand("../../priv/repo/sql/20261001150000_import_download_requests.sql", __DIR__)
      ),
      [],
      query_type: :text
    )

    Ownership.put!(Repo, "command:imports.process_gpx", :oban)
    Ownership.put!(Repo, "command:imports.prepare_download", :oban)
    root = Path.join(System.tmp_dir!(), "native-download-http-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    config = %{service: "local", root: root}
    Application.put_env(:dawarich, :imports_storage, config)

    on_exit(fn ->
      Application.delete_env(:dawarich, :imports_storage)
      File.rm_rf!(root)
    end)

    %{user: Dawarich.Accounts.get(user.id), config: config}
  end

  defp import!(c, name, bytes, original \\ nil) do
    blob =
      Dawarich.RailsBlobFixture.create!(Repo, c.config.root, name, bytes,
        content_type: "application/gpx+xml",
        user_id: c.user.id
      )

    descriptor =
      if original,
        do: %{
          "signed_id" => blob.signed_id,
          "original_filename" => original,
          "client_wrapped" => true
        },
        else: blob.signed_id

    {:ok, [id]} =
      UploadCreate.create(Repo, c.user, [descriptor], %{storage: c.config, self_hosted?: true})

    id
  end

  test "plain verified blob streams all bytes through native HTTP with correct filename", c do
    bytes = "<gpx><trk><name>native streamed bytes</name></trk></gpx>"
    id = import!(c, "download.gpx", bytes)
    conn = get(RailsUser.signed_in(c.user.id), "/imports/#{id}/download")
    assert conn.status == 200
    assert conn.resp_body == bytes
    assert Plug.Conn.get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]
    assert hd(Plug.Conn.get_resp_header(conn, "content-disposition")) =~ "download.gpx"
    other = RailsUser.insert!(%{id: 7598, email: "foreign-download@example.test"})
    path = "/imports/#{id}/download"

    assert {{"GET " <> ^path <> " HTTP/1.1", ""}, %{status: 204}} =
             forwarded(upstream!(), fn -> get(RailsUser.signed_in(other.id), path) end)
  end

  test "a missing import blob returns a native unavailable response", c do
    Dawarich.Test.ImportsExportsSeeds.import!(%{
      id: 759_701,
      user_id: c.user.id,
      name: "bare.gpx"
    })

    conn = get(RailsUser.signed_in(c.user.id), "/imports/759701/download")
    assert conn.status == 404
    assert Plug.Conn.get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]
  end

  test "wrapped blob returns native pending cache and original archive remains immediately downloadable",
       c do
    {:ok, {_, zip}} = :zip.create(~c"wrapped.zip", [{~c"wrapped.gpx", "<gpx/>"}], [:memory])
    id = import!(c, "wrapped.gpx.zip", zip, "wrapped.gpx")
    conn = get(RailsUser.signed_in(c.user.id), "/imports/#{id}/download")
    assert conn.status == 202
    assert Plug.Conn.get_resp_header(conn, "refresh") == ["3"]
    assert conn.resp_body =~ "Preparing your download"
    conn = get(RailsUser.signed_in(c.user.id), "/imports/#{id}/download")
    assert conn.status == 202

    assert [[1]] =
             Repo.query!(
               "SELECT count(*) FROM job_outbox WHERE command_type='imports.prepare_download'"
             ).rows

    conn = get(RailsUser.signed_in(c.user.id), "/imports/#{id}/download?original=1")
    assert conn.status == 200
    assert conn.resp_body == zip
  end

  @tag :g44_imports_zip
  test "standalone preparing page archive link returns the original zip through the browser envelope",
       c do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    {:ok, {_, zip}} = :zip.create(~c"wrapped.zip", [{~c"wrapped.gpx", "<gpx/>"}], [:memory])
    id = import!(c, "wrapped.gpx.zip", zip, "wrapped.gpx")

    Repo.query!(
      "UPDATE active_storage_blobs SET content_type='application/zip' WHERE id=(SELECT blob_id FROM active_storage_attachments WHERE record_type='Import' AND record_id=$1 AND name='file')",
      [id]
    )

    pending = RailsUser.signed_in(c.user.id) |> get("/imports/#{id}/download")
    assert pending.status == 202

    [href] =
      pending.resp_body
      |> LazyHTML.from_document()
      |> LazyHTML.query("a[data-turbo=false][href*=original]")
      |> LazyHTML.attribute("href")

    Process.put(:g44_download_preparation, {c.user.id, id, %{services: %{"local" => c.config}}})
    previous_repo = Application.fetch_env(:dawarich, :imports_repo)
    Application.put_env(:dawarich, :imports_repo, PreparingRepo)

    on_exit(fn ->
      case previous_repo do
        {:ok, repo} -> Application.put_env(:dawarich, :imports_repo, repo)
        :error -> Application.delete_env(:dawarich, :imports_repo)
      end
    end)

    conn =
      RailsUser.signed_in(c.user.id) |> Plug.Conn.put_req_header("accept", "*/*") |> get(href)

    assert conn.status == 200
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["application/zip; charset=utf-8"]
    assert conn.resp_body == zip
    assert hd(Plug.Conn.get_resp_header(conn, "content-disposition")) =~ "wrapped.gpx.zip"
  end

  test "empty current catalog returns a native error without an upstream", c do
    id = import!(c, "historical.gpx", "<gpx/>")
    Application.delete_env(:dawarich, :imports_storage)
    Application.put_env(:dawarich, :imports_services, %{})
    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, 0})

    on_exit(fn ->
      Application.delete_env(:dawarich, :imports_services)
      Application.put_env(:dawarich, :rails_upstream, previous)
    end)

    conn = get(RailsUser.signed_in(c.user.id), "/imports/#{id}/download")
    assert conn.status == 422
    assert Plug.Conn.get_resp_header(conn, "x-dawarich-handler") == ["phoenix-imports"]
  end
end
