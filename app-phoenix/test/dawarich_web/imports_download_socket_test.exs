defmodule DawarichWeb.ImportsDownloadSocketTest do
  use Dawarich.IngestCase, async: false
  alias Dawarich.Imports.UploadCreate
  alias Dawarich.Test.RailsUser

  defmodule Probe do
    def init(opts), do: opts

    def call(conn, owner) do
      result = DawarichWeb.Endpoint.call(conn, DawarichWeb.Endpoint.init([]))
      send(owner, {:http_completed, result.halted})
      result
    end
  end

  test "real HTTP consumes every byte before cleanup and disconnect closes the verified tempfile" do
    user = RailsUser.insert!(%{id: 7599, email: "download-socket@example.test"})
    root = Path.join(System.tmp_dir!(), "socket-storage-" <> Ecto.UUID.generate())
    temp = Path.join(root, "temporary")
    File.mkdir_p!(temp)
    config = %{service: "local", root: root}

    for {key, value} <- [imports_storage: config, imports_temp_dir: temp] do
      Application.put_env(:dawarich, key, value)
      on_exit(fn -> Application.delete_env(:dawarich, key) end)
    end

    on_exit(fn -> File.rm_rf!(root) end)
    bytes = "<gpx/>" <> String.duplicate(" ", 16 * 1024 * 1024)

    blob =
      Dawarich.RailsBlobFixture.create!(Repo, root, "socket.gpx", bytes,
        content_type: "application/gpx+xml",
        user_id: user.id
      )

    {:ok, [id]} =
      UploadCreate.create(Repo, user, [blob.signed_id], %{storage: config, self_hosted?: true})

    server = start_supervised!({Bandit, plug: {Probe, self()}, port: 0, ip: {127, 0, 0, 1}})
    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    cookie = RailsUser.cookie(RailsUser.session(user.id))
    url = ~c"http://127.0.0.1:#{port}/imports/#{id}/download"

    {:ok, {{_, 200, _}, headers, body}} =
      :httpc.request(
        :get,
        {url, [{~c"cookie", String.to_charlist("_dawarich_session=" <> cookie)}]},
        [timeout: 10_000],
        body_format: :binary
      )

    assert body == bytes
    assert {~c"x-dawarich-handler", ~c"phoenix-imports"} in headers
    assert_receive {:http_completed, false}, 5_000
    assert File.ls!(temp) == []

    {:ok, socket} =
      :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false, recbuf: 1024], 5_000)

    :ok =
      :gen_tcp.send(
        socket,
        "GET /imports/#{id}/download HTTP/1.1\r\nHost: 127.0.0.1:#{port}\r\nCookie: _dawarich_session=#{cookie}\r\nConnection: close\r\n\r\n"
      )

    assert {:ok, data} = :gen_tcp.recv(socket, 0, 5_000)
    assert data =~ "200 OK"
    :ok = :gen_tcp.close(socket)
    assert_receive {:http_completed, true}, 5_000
    assert File.ls!(temp) == []
  end
end
