defmodule DawarichWeb.A12f2IClosureTest do
  use Dawarich.IngestCase

  import Plug.Conn
  import Plug.Test

  alias Dawarich.{RailsMessages, Storage}
  alias Dawarich.Storage.Blobs
  alias DawarichWeb.ActiveStorage.Proxy

  @payload :binary.copy(:binary.list_to_bin(Enum.to_list(0..255)), 4)
  @now ~U[2026-10-02 12:00:00Z]
  @compared ~w(content-type content-disposition content-length content-range last-modified cache-control location etag)

  defmodule S3Client do
    @behaviour ExAws.Request.HttpClient
    def request(method, _url, _body, headers, opts) do
      send(self(), {:provider_request, method, Map.new(headers)})
      opts[:respond].(method, Map.new(headers))
    end
  end

  setup do
    root = Path.join(System.tmp_dir!(), "a12f2i-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf(root) end)
    fx = "test/fixtures/a12b/storage.json" |> File.read!() |> Jason.decode!()

    for row <- fx["blobs"] do
      Repo.query!(
        "INSERT INTO active_storage_blobs(id,key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)",
        [row["id"], row["key"], row["filename"], row["content_type"], Jason.encode!(row["metadata"]), row["service_name"], row["byte_size"], row["checksum"], DateTime.to_naive(@now)]
      )
      if row["stored"] do
        path = Storage.disk_path(root, row["key"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, @payload)
      end
    end

    %{storage: %{default: "test", services: %{"test" => %{service: "local", root: root}, "local" => %{service: "local", root: root}}}, root: root}
  end

  @tag :a12f2_i_02
  test "Blob proxy preserves signed IDs attachment headers ranges conditional HEAD and local S3 failures", %{storage: storage} do
    assert Code.ensure_loaded?(Proxy), "native blob proxy handler must exist"
    fx = closure()
    for request <- Enum.filter(fx["requests"], &String.starts_with?(&1["name"], "proxy_")) do
      conn = replay(request, Proxy, storage)
      assert_response(conn, request)
    end
    blob = Blobs.find(970_501)
    signed = RailsMessages.blob_id(blob.id)
    conn = conn(:get, "/proxy/#{signed}/x")
    conn = %{conn | path_params: %{"signed_id" => signed, "filename" => ["x"]}}
    absent = %{storage | services: %{"test" => %{service: "local", root: "/absent"}}}
    assert apply(Proxy, :call, [conn, [storage: absent, now: @now]]).status == 404
    conn = put_req_header(conn, "range", "bytes=0-1,4-5")
    multi = apply(Proxy, :call, [conn, [storage: storage, now: @now, boundary: "synthetic"]])
    assert multi.status == 206
    assert multi.resp_body =~ "Content-Range: bytes 0-1/1024"
    assert multi.resp_body =~ "Content-Range: bytes 4-5/1024"
    cfg = Storage.config!(%{"STORAGE_BACKEND" => "s3", "AWS_ACCESS_KEY_ID" => "synthetic", "AWS_SECRET_ACCESS_KEY" => "synthetic", "AWS_REGION" => "eu-central-1", "AWS_BUCKET" => "synthetic", "AWS_ENDPOINT_URL" => "http://127.0.0.1:1"})
    for status <- [404, 403] do
      respond = fn _, _ -> {:ok, %{status_code: status, headers: [], body: ""}} end
      service = %{cfg | ex_aws: Keyword.merge(cfg.ex_aws, http_client: S3Client, http_opts: [respond: respond], retries: [max_attempts: 1])}
      registry = %{storage | services: %{"test" => service}}
      plain = delete_req_header(conn, "range")
      assert apply(Proxy, :call, [plain, [storage: registry, now: @now]]).status == if(status == 404, do: 404, else: 500)
    end
    respond = fn :get, headers ->
      assert headers["range"] == "bytes=0-9"
      {:ok, %{status_code: 206, headers: [], body: binary_part(@payload, 0, 10)}}
    end
    service = %{cfg | ex_aws: Keyword.merge(cfg.ex_aws, http_client: S3Client, http_opts: [respond: respond])}
    registry = %{storage | services: %{"test" => service}}
    s3_range = put_req_header(conn, "range", "bytes=0-9")
    result = apply(Proxy, :call, [s3_range, [storage: registry, now: @now]])
    assert {result.status, result.resp_body} == {206, binary_part(@payload, 0, 10)}
  end

  defp closure, do: "test/fixtures/a12f2i/closure.json" |> File.read!() |> Jason.decode!()

  defp replay(request, module, storage, opts \\ []) do
    uri = URI.parse(request["path"])
    pieces = uri.path |> String.split("/", trim: true) |> Enum.map(&URI.decode/1)
    params = case pieces do
      ["rails", "active_storage", "blobs", "proxy", signed | filename] -> %{"signed_id" => signed, "filename" => filename}
      ["rails", "active_storage", "representations", mode, signed, variation | filename] when mode in ["proxy", "redirect"] -> %{"signed_blob_id" => signed, "variation_key" => variation, "filename" => filename}
      ["rails", "active_storage", "representations", signed, variation | filename] -> %{"signed_blob_id" => signed, "variation_key" => variation, "filename" => filename}
    end
    conn = Enum.reduce(request["headers"], conn(request["method"], "http://dawarich.example" <> request["path"]), fn {name, value}, conn -> put_req_header(conn, String.downcase(name), value) end)
    apply(module, :call, [%{conn | path_params: params}, Keyword.merge([storage: storage, now: @now], opts)])
  end

  defp assert_response(conn, request) do
    assert conn.status == request["status"], "#{request["name"]}: #{conn.status} != #{request["status"]}"
    for header <- @compared do
      assert get_resp_header(conn, header) == List.wrap(request["response_headers"][header]), "#{request["name"]} #{header}"
    end
    unless request["method"] == "HEAD", do: assert(conn.resp_body == Base.decode64!(request["response_body"]), request["name"])
  end
end
