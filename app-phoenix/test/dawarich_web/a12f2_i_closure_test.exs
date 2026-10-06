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

  @tag :a12f2_i_03
  test "Representation resolution preserves source variation signatures transforms purpose and legacy error responses", %{storage: storage} do
    module = Dawarich.Storage.Variation
    assert Code.ensure_loaded?(module), "native variation verifier must exist"
    fx = closure()
    assert {:ok, variation} = apply(module, :decode, [fx["variation"]["key"], @now])
    assert variation.transformations == fx["variation"]["transformations"]
    assert {:ok, legacy} = apply(module, :decode, [fx["legacy_variation"], @now])
    assert legacy.transformations == variation.transformations
    assert apply(module, :decode, [fx["variation"]["key"] <> "x", @now]) == :error
    for purpose <- ["blob_id", "blob_key", "", "variation"] do
      token = RailsMessages.sign_storage(fx["variation"]["transformations"], purpose, DateTime.add(@now, 1))
      if purpose == "variation", do: assert(match?({:ok, _}, apply(module, :decode, [token, @now]))), else: assert(apply(module, :decode, [token, @now]) == :error)
      assert apply(module, :decode, [token, DateTime.add(@now, 1)]) == :error
    end
    for request <- Enum.filter(fx["requests"], &(&1["name"] in ["representation_bad_signature", "representation_wrong_purpose"])) do
      assert_response(replay(request, DawarichWeb.ActiveStorage.Representations, storage), request)
    end
  end

  @tag :a12f2_i_04
  test "Representation redirect and proxy preserve image bytes variation identity persisted reuse and source failures", %{storage: storage, root: root} do
    module = Dawarich.Storage.Representations
    assert Code.ensure_loaded?(module), "native representation processing must exist"
    fx = closure()
    for request <- Enum.filter(fx["requests"], &(&1["name"] in ["representation_proxy", "representation_redirect", "representation_legacy", "representation_non_image"])) do
      assert_response(replay(request, DawarichWeb.ActiveStorage.Representations, storage, key: fn -> "a12b" <> String.duplicate("v", 24) end), request)
    end
    assert Repo.query!("SELECT count(*) FROM active_storage_variant_records").rows == [[1]]
    key = fx["representation"]["key"]
    assert File.read!(Storage.disk_path(root, key)) == Base.decode64!(fx["representation"]["bytes"])
    assert File.read!(Storage.disk_path(root, key)) == @payload
    for preview <- fx["previews"] do
      row = preview["blob"]
      bytes = Base.decode64!(preview["bytes"])
      Repo.query!("INSERT INTO active_storage_blobs(id,key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)", [row["id"],row["key"],row["filename"],row["content_type"],Jason.encode!(row["metadata"]),row["service_name"],row["byte_size"],row["checksum"],DateTime.to_naive(@now)])
      path = Storage.disk_path(root, row["key"])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes)
      result = replay(preview["request"], DawarichWeb.ActiveStorage.Representations, storage, key: fn -> preview["key"] end)
      assert_response(result, preview["request"])
    end
    first = Blobs.find(970_503)
    assert {:ok, variation} = Dawarich.Storage.Variation.decode(fx["variation"]["key"], @now)
    assert {:ok, image} = apply(module, :processed, [first, variation, storage, @now, []])
    assert image.key == key
    defaulted = Dawarich.Storage.Variation.default(variation, "png")
    assert Dawarich.Storage.Variation.marshal(defaulted) == Base.decode64!(fx["representation"]["marshal"])
    assert Dawarich.Storage.Variation.digest(defaulted) == fx["representation"]["digest"]
    assert Repo.query!("SELECT count(*) FROM active_storage_variant_records").rows == [[1]]
    File.rm!(Storage.disk_path(root, first.key))
    assert {:ok, reused} = apply(module, :processed, [first, variation, storage, @now, []])
    assert reused.key == image.key
    assert {:ok, bad} = Dawarich.Storage.Variation.decode(RailsMessages.sign_storage(%{"format" => "unknown"}, "variation", DateTime.add(@now, 1)), @now)
    assert {:error, :invalid_format} = apply(module, :processed, [first, bad, storage, @now, []])
  end

  @tag :a12f2_i_05
  test "Disk redirect and direct upload retain guest CSRF legacy session body formats service config and terminal persistence", %{storage: storage} do
    module = DawarichWeb.ActiveStorage.UploadClosure
    assert Code.ensure_loaded?(module), "native upload closure must exist"
    guest = closure()["guest"]
    Repo.query!("SELECT setval('active_storage_blobs_id_seq',972000)")
    {:ok, keys} = Agent.start_link(fn -> Enum.map(~w(u w x y z), &("a12b" <> String.duplicate(&1,24))) end)
    on_exit(fn -> if Process.alive?(keys), do: Agent.stop(keys) end)
    key = fn -> Agent.get_and_update(keys, fn [key|rest] -> {key, rest} end) end
    for request <- guest["requests"] do
      body = Base.decode64!(request["body"])
      conn = Enum.reduce(request["headers"], conn(:post, "http://dawarich.example" <> request["path"], body), fn {name,value}, conn -> put_req_header(conn, String.downcase(String.replace(name,"CONTENT_","content-")), value) end)
      conn = conn |> put_req_header("cookie", "_dawarich_session=" <> URI.encode_www_form(guest["cookie"])) |> DawarichWeb.RailsAuth.call([])
      refute conn.assigns[:current_user]
      conn = if request["csrf"], do: put_req_header(conn,"x-csrf-token",guest["csrf"]), else: conn
      before = blob_count()
      result = DawarichWeb.ActiveStorage.call(conn, action: :direct_upload, storage: storage, now: @now, key: key, zone: "Europe/Berlin")
      assert_response(result, request)
      assert blob_count() == before + if(result.status == 200, do: 1, else: 0)
    end
    session = %{"_csrf_token" => DawarichWeb.RailsCsrf.new_token()}
    token = DawarichWeb.RailsCsrf.masked_token(session)
    body = Jason.encode!(%{"blob" => %{"filename" => "large.png", "byte_size" => 1, "checksum" => "synthetic", "metadata" => %{"note" => String.duplicate("p",1_100_000)}}})
    conn = conn(:post,"http://dawarich.example/rails/active_storage/direct_uploads",body) |> put_req_header("content-type","application/json") |> put_req_header("transfer-encoding","chunked") |> put_req_header("x-csrf-token",token) |> assign(:rails_session,session)
    result = DawarichWeb.ActiveStorage.call(conn, action: :direct_upload, storage: storage, now: @now, key: key)
    assert result.status == 200
    assert byte_size(Jason.decode!(result.resp_body)["metadata"]["note"]) == 1_100_000
  end

  @tag :a12f2_i_06
  test "Storage failures after accepted file blob or variant effects never replay into a second Rails operation", %{storage: storage, root: root} do
    {:ok, listener} = :gen_tcp.listen(0, [:binary, active: false, ip: {127,0,0,1}])
    {:ok, {_,port}} = :inet.sockname(listener)
    on_exit(fn -> :gen_tcp.close(listener) end)
    upstream = {{127,0,0,1}, port}
    owner = self()
    start_supervised!({Task, fn ->
      case :gen_tcp.accept(listener) do
        {:ok, socket} ->
          send(owner, :rails_replay)
          {_head, _rest} = Dawarich.Test.RawHTTP.read_head(socket)
          :gen_tcp.send(socket, "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
          :gen_tcp.close(socket)
        {:error, :closed} -> :ok
      end
    end})
    session = %{"_csrf_token" => DawarichWeb.RailsCsrf.new_token()}
    token = DawarichWeb.RailsCsrf.masked_token(session)
    body = Jason.encode!(%{"blob" => %{"filename" => "accepted.png", "byte_size" => 1024, "checksum" => "synthetic"}})
    conn = conn(:post,"http://dawarich.example/rails/active_storage/direct_uploads",body) |> put_req_header("content-type","application/json") |> put_req_header("accept","application/json") |> put_req_header("x-csrf-token",token) |> assign(:rails_session,session)
    before = blob_count()
    result = DawarichWeb.ActiveStorage.call(conn, action: :direct_upload, storage: storage, now: @now, key: fn -> "a12b" <> String.duplicate("t",24) end, upstream: upstream, after_blob: fn _ -> raise "synthetic response failure" end)
    refute_received :rails_replay
    assert result.status == 500
    assert blob_count() == before + 1
    fx = closure()
    assert {:ok, variation} = Dawarich.Storage.Variation.decode(fx["variation"]["key"], @now)
    blob = Blobs.find(970_503)
    before = blob_count()
    assert {:error, :processing} = Dawarich.Storage.Representations.processed(blob, variation, storage, @now, after_variant_insert: fn _ -> raise "synthetic SQL failure" end)
    assert blob_count() == before
    assert Repo.query!("SELECT count(*) FROM active_storage_variant_records").rows == [[0]]
    key = "a12b" <> String.duplicate("o",24)
    assert {:error, :processing} = Dawarich.Storage.Representations.processed(blob, variation, storage, @now, key: fn -> key end, after_put: fn _ -> raise "synthetic put failure" end)
    assert blob_count() == before + 1
    assert Repo.query!("SELECT count(*) FROM active_storage_variant_records").rows == [[1]]
    assert File.read!(Storage.disk_path(root,key)) == @payload
    assert {:ok, reused} = Dawarich.Storage.Representations.processed(blob, variation, storage, @now)
    assert reused.key == key
    assert blob_count() == before + 1
    request = Enum.find(fx["requests"], &(&1["name"] == "proxy_plain"))
    streamed = replay(request, Proxy, storage, after_chunk: fn _ -> raise "synthetic partial send" end)
    assert streamed.status == 200
    assert streamed.halted
    assert streamed.resp_body == @payload
    refute_received :rails_replay
    assert Path.wildcard(Path.join(root,".phoenix-tmp/*")) == []
  end

  defp blob_count, do: Repo.query!("SELECT count(*) FROM active_storage_blobs").rows |> hd() |> hd()

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
