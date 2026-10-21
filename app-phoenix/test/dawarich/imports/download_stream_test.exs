defmodule Dawarich.Test.ImportDownloadPlug do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    {:ok, {conn, path}} =
      Dawarich.Imports.Download.with_file(
        Dawarich.ScratchRepo,
        opts.user,
        opts.id,
        opts.context,
        fn path, name, type ->
          conn =
            conn
            |> put_resp_content_type(type)
            |> put_resp_header(
              "content-disposition",
              Dawarich.Storage.content_disposition("attachment", name)
            )
            |> send_chunked(200)

          send(opts.parent, {:stream_ready, path, self()})
          if opts.pause, do: receive(do: (:stream -> :ok))

          conn =
            path
            |> File.stream!(65_536)
            |> Enum.reduce_while(conn, fn bytes, conn ->
              case chunk(conn, bytes) do
                {:ok, conn} -> {:cont, conn}
                {:error, _} -> {:halt, conn}
              end
            end)

          send(opts.parent, {:stream_returned, path})
          {conn, path}
        end
      )

    send(opts.parent, {:stream_cleaned, path})
    conn
  end
end

defmodule Dawarich.Imports.DownloadStreamTest do
  use Dawarich.JobsCase
  alias Dawarich.Imports.Download

  setup do
    f = Dawarich.ImportLeaseFixture.create()
    root = Path.join(System.tmp_dir!(), "http-download-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    context = %{services: %{"local" => %{service: "local", root: root}}, temp_dir: root}

    bytes =
      "<gpx><name>Rhéin</name>" <>
        String.duplicate("<trkpt lat=\"50\" lon=\"8\"/>", 100_000) <> "</gpx>"

    archive = Path.join(root, "fixture.zip")
    Dawarich.GpxZipFixture.write!(archive, [{"ride.gpx", bytes, [flags: 8]}])
    key = Dawarich.Storage.generate_key()
    source = Dawarich.Storage.disk_path(root, key)
    File.mkdir_p!(Path.dirname(source))
    File.rename!(archive, source)
    {checksum, size} = Dawarich.Storage.digest_file!(source)

    [[blob]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,byte_size,checksum,service_name,created_at) VALUES ($1,'ride.gpx.zip',$2,$3,'local',now()) RETURNING id",
        [key, size, checksum]
      )

    rows(
      "INSERT INTO active_storage_attachments(record_type,record_id,name,blob_id,created_at) VALUES ('Import',$1,'file',$2,now())",
      [f.import.id, blob]
    )

    assert :ok = Download.prepare!(ScratchRepo, f.import.user_id, f.import.id, blob, context)
    Map.merge(f, %{root: root, context: context, bytes: bytes})
  end

  defp server(c, pause) do
    opts = %{
      user: c.import.user_id,
      id: c.import.id,
      context: c.context,
      parent: self(),
      pause: pause
    }

    pid =
      start_supervised!(
        {Bandit,
         plug: {Dawarich.Test.ImportDownloadPlug, opts},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false},
        id: make_ref()
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    port
  end

  test "actual Bandit chunked HTTP returns complete prepared bytes and cleans after body", c do
    port = server(c, false)
    socket = Dawarich.Test.RawHTTP.connect(port)

    Dawarich.Test.RawHTTP.send_raw(
      socket,
      "GET /download HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    )

    {200, headers, body} = Dawarich.Test.RawHTTP.read_response(socket)
    :gen_tcp.close(socket)
    assert body == c.bytes
    assert {"transfer-encoding", "chunked"} in headers

    assert Enum.any?(headers, fn {key, value} ->
             key == "content-disposition" and value =~ "lease.gpx"
           end)

    {:stream_ready, path, _process} =
      receive do: ({:stream_ready, _, _} = message -> message)

    receive do: ({:stream_returned, ^path} -> :ok)
    receive do: ({:stream_cleaned, ^path} -> :ok)
    clean(c)
  end

  test "actual HTTP socket disconnect halts stream and cleans verified prepared file", c do
    port = server(c, true)
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])

    :ok =
      :gen_tcp.send(
        socket,
        "GET /download HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
      )

    {:stream_ready, path, process} =
      receive do: ({:stream_ready, _, _} = message -> message)

    assert File.exists?(path)
    {:ok, headers} = :gen_tcp.recv(socket, 0, :infinity)
    assert headers =~ "200 OK"
    assert String.downcase(headers) =~ "transfer-encoding: chunked"
    :ok = :gen_tcp.close(socket)
    send(process, :stream)
    receive do: ({:stream_returned, ^path} -> :ok)
    receive do: ({:stream_cleaned, ^path} -> :ok)
    clean(c)
  end

  test "a download mid-stream holds no lock on the user or the import", c do
    port = server(c, true)
    socket = Dawarich.Test.RawHTTP.connect(port)

    Dawarich.Test.RawHTTP.send_raw(
      socket,
      "GET /download HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    )

    {:stream_ready, path, process} =
      receive do: ({:stream_ready, _, _} = message -> message)

    assert {:ok, [[1], [1]]} =
             ScratchRepo.transaction(fn ->
               rows("SELECT 1 FROM users WHERE id=$1 FOR NO KEY UPDATE NOWAIT", [c.import.user_id])

               rows("UPDATE users SET updated_at=now() WHERE id=$1", [c.import.user_id])
               [[1]] = rows("SELECT 1 FROM imports WHERE id=$1 FOR UPDATE NOWAIT", [c.import.id])
               [[1], [1]]
             end)

    send(process, :stream)
    {200, _headers, body} = Dawarich.Test.RawHTTP.read_response(socket)
    :gen_tcp.close(socket)
    assert body == c.bytes
    receive do: ({:stream_returned, ^path} -> :ok)
    receive do: ({:stream_cleaned, ^path} -> :ok)
    clean(c)
  end

  defp clean(c),
    do:
      assert(
        Enum.flat_map(["import-*", "unzipped-*"], &Path.wildcard(Path.join(c.root, &1))) == []
      )
end
