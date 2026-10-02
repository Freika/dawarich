defmodule DawarichWeb.ImportsDownloadTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  alias Dawarich.Test.RailsUser
  alias Dawarich.Imports.{Uploads, UploadCreate}
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
    attrs = %{
      "filename" => name,
      "byte_size" => byte_size(bytes),
      "checksum" => Base.encode64(:crypto.hash(:md5, bytes)),
      "content_type" => "application/gpx+xml"
    }

    {:ok, blob} = Uploads.reserve(Repo, c.user, attrs, c.config)
    path = Path.join(c.config.root, "input")
    File.write!(path, bytes)
    :ok = Uploads.write(Repo, c.user, blob.upload_token, path, c.config)

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
    conn = get(RailsUser.signed_in(other.id), "/imports/#{id}/download")
    assert conn.status == 404
    refute conn.resp_body =~ "native streamed bytes"
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

  test "empty current catalog reaches historical storage Rails handback", c do
    id = import!(c, "historical.gpx", "<gpx/>")
    Application.delete_env(:dawarich, :imports_storage)
    Application.put_env(:dawarich, :imports_services, %{})
    upstream = Dawarich.Test.RawHTTP.listen()
    previous = Application.get_env(:dawarich, :rails_upstream)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      Application.delete_env(:dawarich, :imports_services)
      Application.put_env(:dawarich, :rails_upstream, previous)
    end)

    reply =
      Task.async(fn ->
        socket = Dawarich.Test.RawHTTP.accept(upstream)
        {head, _} = Dawarich.Test.RawHTTP.read_head(socket)
        assert Dawarich.Test.RawHTTP.request_line(head) == "GET /imports/#{id}/download HTTP/1.1"
        Dawarich.Test.RawHTTP.reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 6\r\n\r\nlegacy")
      end)

    conn = get(RailsUser.signed_in(c.user.id), "/imports/#{id}/download")
    assert conn.status == 200
    assert conn.resp_body == "legacy"
    assert Plug.Conn.get_resp_header(conn, "x-dawarich-handler") == ["rails-imports"]
    Task.await(reply)
  end
end
