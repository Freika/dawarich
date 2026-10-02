defmodule DawarichWeb.ActiveStorageTest do
  use Dawarich.IngestCase

  import Plug.Conn
  import Plug.Test

  alias Dawarich.Storage
  alias Dawarich.Test.A12b
  alias DawarichWeb.{ActiveStorage, RailsAuth}
  alias DawarichWeb.ActiveStorage.FileServer

  @fx A12b.fixture("storage.json")
  @compared ~w(content-type content-disposition content-range last-modified cache-control location etag)
  @payload :binary.copy(:binary.list_to_bin(Enum.to_list(0..255)), 4)

  setup do
    root = Path.join(System.tmp_dir!(), "a12b-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(root) end)
    mtime = DateTime.to_unix(~U[2026-10-01 12:00:00Z])

    for row <- @fx["blobs"] do
      {:ok, created_at, 0} = DateTime.from_iso8601(row["created_at"])

      Repo.query!(
        "INSERT INTO active_storage_blobs (id, key, filename, content_type, metadata, service_name, byte_size, checksum, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)",
        [
          row["id"],
          row["key"],
          row["filename"],
          row["content_type"],
          Jason.encode!(row["metadata"]),
          row["service_name"],
          row["byte_size"],
          row["checksum"],
          DateTime.to_naive(created_at)
        ]
      )

      if row["stored"] do
        path = Storage.disk_path(root, row["key"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, @payload)
        File.touch!(path, mtime)
      end
    end

    %{storage: %{service: "local", root: root, stored_service: "test"}}
  end

  defp route("GET", "/rails/active_storage/disk/" <> rest) do
    [encoded, filename] = String.split(rest, "/", parts: 2)

    {:disk,
     %{
       "encoded_key" => URI.decode(encoded),
       "filename" => String.split(URI.decode(filename), "/")
     }}
  end

  defp route("HEAD", path), do: route("GET", path)

  defp route("PUT", "/rails/active_storage/disk/" <> encoded),
    do: {:disk_update, %{"encoded_token" => URI.decode(encoded)}}

  defp route("POST", "/rails/active_storage/direct_uploads"), do: {:direct_upload, %{}}

  defp route("GET", "/rails/active_storage/blobs/" <> rest) do
    [signed | filename] =
      rest |> String.trim_leading("redirect/") |> String.split("?") |> hd() |> String.split("/")

    {:redirect,
     %{"signed_id" => URI.decode(signed), "filename" => Enum.map(filename, &URI.decode/1)}}
  end

  defp replay(request, storage, extra_headers) do
    {action, params} = route(request["method"], request["path"])
    {:ok, now, 0} = DateTime.from_iso8601(request["now"])
    body = if request["body"], do: Base.decode64!(request["body"]), else: ""

    conn =
      Enum.reduce(
        Map.merge(request["headers"], extra_headers),
        conn(request["method"], "http://dawarich.example" <> request["path"], body),
        fn
          {"CONTENT_TYPE", value}, conn -> put_req_header(conn, "content-type", value)
          {"CONTENT_LENGTH", value}, conn -> put_req_header(conn, "content-length", value)
          {name, value}, conn -> put_req_header(conn, String.downcase(name), value)
        end
      )

    conn =
      if body == "" or get_req_header(conn, "content-length") != [],
        do: conn,
        else: put_req_header(conn, "content-length", Integer.to_string(byte_size(body)))

    conn = %{conn | path_params: params} |> RailsAuth.call([])

    ActiveStorage.call(
      conn,
      ActiveStorage.init(
        action: action,
        storage: storage,
        now: now,
        key: fn -> "a12b" <> String.duplicate("h", 24) end,
        zone: @fx["direct_upload"]["time_zone"]
      )
    )
  end

  defp assert_replayed(conn, request) do
    name = request["name"]
    assert conn.status == request["status"], name

    for header <- @compared,
        do:
          assert(
            get_resp_header(conn, header) == List.wrap(request["response_headers"][header]),
            "#{name} #{header}"
          )

    unless request["method"] == "HEAD" do
      assert conn.resp_body == Base.decode64!(request["response_body"]), name

      if length = request["response_headers"]["content-length"],
        do:
          assert(byte_size(conn.resp_body) == String.to_integer(length), "#{name} content-length")
    end
  end

  test "replays every recorded disk, upload and redirect request with Rails' status, headers and body",
       %{storage: storage} do
    {[multi], rest} = Enum.split_with(@fx["requests"], &(&1["name"] == "disk_multi"))

    for request <- rest, do: assert_replayed(replay(request, storage, %{}), request)

    conn = replay(multi, storage, %{})
    assert {conn.status, conn.resp_body} == {200, @payload}

    stored = Storage.disk_path(storage.root, "a12b" <> String.duplicate("f", 24))
    assert File.read!(stored) == @payload
    refute File.exists?(Storage.disk_path(storage.root, "a12b" <> String.duplicate("g", 24)))
  end

  test "replays the direct-upload requests, the created blob and its JSON byte for byte",
       %{storage: storage} do
    Repo.query!("SELECT setval('active_storage_blobs_id_seq', 970599)")

    cookie = %{
      "cookie" =>
        "_dawarich_session=" <> URI.encode_www_form(@fx["direct_upload"]["session_cookie"])
    }

    for request <- @fx["upload_requests"] do
      csrf =
        if request["csrf"],
          do: %{"x-csrf-token" => @fx["direct_upload"]["csrf_meta"]},
          else: %{}

      assert_replayed(replay(request, storage, Map.merge(cookie, csrf)), request)
    end
  end

  test "byte_ranges/2 is Rack::Utils.get_byte_ranges" do
    zeros = fn n -> "bytes=" <> Enum.map_join(1..n, ",", fn _ -> "0-0" end) end

    cases = [
      {["bytes=0-9"], [{0, 9}]},
      {["bytes=-5"], [{1019, 1023}]},
      {["bytes=1000-"], [{1000, 1023}]},
      {["bytes=1020-99999"], [{1020, 1023}]},
      {["bytes=999999-"], []},
      {["bytes=9-0"], nil},
      {["bytes=0-1,4-5"], [{0, 1}, {4, 5}]},
      {["bytes=-"], nil},
      {["bytes=5"], nil},
      {["bytes=1-2-3"], [{1, 2}]},
      {["items=0-1"], nil},
      {[], nil},
      {[zeros.(100)], List.duplicate({0, 0}, 100)},
      {[zeros.(101)], nil},
      {["bytes=0-1,"], [{0, 1}]},
      {["bytes=0-2000"], [{0, 1023}]}
    ]

    for {header, expected} <- cases,
        do: assert(FileServer.byte_ranges(header, 1024) == expected, inspect(header))

    assert FileServer.byte_ranges(["bytes=0-1"], 0) == nil
  end
end
