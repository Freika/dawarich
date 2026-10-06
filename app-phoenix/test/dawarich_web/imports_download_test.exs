defmodule DawarichWeb.ImportsDownloadTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Dawarich.Test.RailsFormRequests, only: [upstream!: 0, forwarded: 2]
  alias Dawarich.Test.RailsUser
  alias Dawarich.Imports.UploadCreate
  alias Dawarich.Jobs.Ownership
  @endpoint DawarichWeb.Endpoint
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
        content_type: "application/gpx+xml"
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
