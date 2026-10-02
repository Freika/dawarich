defmodule Dawarich.Storage.ReaderTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias Dawarich.Storage.{Reader, S3}
  alias Dawarich.Test.{DownloadServer, RawHTTP}

  @key "abcd012345678901234567890123"
  @blob %{
    key: @key,
    service_name: "local",
    filename: "../trace.gpx",
    byte_size: 5,
    checksum: "XUFAKrxLKna5cZ2REBfFkg=="
  }

  setup do
    dir =
      Path.join(
        System.tmp_dir!(),
        "storage-reader-" <> Base.encode16(:crypto.strong_rand_bytes(12))
      )

    source = Path.join([dir, "storage", "ab", "cd"])
    File.mkdir_p!(source)
    File.write!(Path.join(source, @key), "hello")
    tmp = Path.join(dir, "tmp")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir, tmp: tmp, config: %{service: "local", root: Path.join(dir, "storage")}}
  end

  test "streams a Rails disk blob to its verified retained path", %{config: config, tmp: tmp} do
    path = Reader.download!(config, @blob, temp_dir: tmp)
    assert File.read!(path) == "hello"
    assert Path.dirname(path) == tmp
    assert File.read!(Path.join([config.root, "ab", "cd", @key])) == "hello"
  end

  test "missing disk blobs fail without retaining a file", %{config: config, tmp: tmp} do
    assert_raise File.Error, fn ->
      Reader.download!(config, %{@blob | key: "missing_blob"}, temp_dir: tmp)
    end

    assert File.ls!(tmp) == []
  end

  test "mismatched services never read another storage root", %{config: config, tmp: tmp} do
    assert_raise ArgumentError, ~r/service/, fn ->
      Reader.download!(config, %{@blob | service_name: "s3"}, temp_dir: tmp)
    end

    assert File.ls!(tmp) == []
  end

  test "rejects traversal and short disk keys before creating a download", %{
    config: config,
    tmp: tmp
  } do
    for key <- ["../secret", "ab/cd/secret", "", "a", "ab", "abc", "abc\\secret"] do
      assert_raise ArgumentError, ~r/key/, fn ->
        Reader.download!(config, %{@blob | key: key}, temp_dir: tmp)
      end
    end

    assert File.ls!(tmp) == []
  end

  test "verifies bytes rather than trusting an existing disk blob", %{config: config, tmp: tmp} do
    File.write!(Path.join([config.root, "ab", "cd", @key]), "jello")

    assert_raise RuntimeError, ~r/Checksum mismatch/, fn ->
      Reader.download!(config, @blob, temp_dir: tmp)
    end

    assert File.ls!(tmp) == []
  end

  test "downloads a signed S3 object using the configured bucket and endpoint", %{tmp: tmp} do
    {url, server} =
      DownloadServer.start(fn socket, head, _ ->
        ["GET", target, "HTTP/1.1"] = String.split(RawHTTP.request_line(head))
        uri = URI.parse(target)
        assert uri.path == "/dawarich/" <> @key
        query = URI.decode_query(uri.query)
        assert query["X-Amz-Algorithm"] == "AWS4-HMAC-SHA256"
        assert query["X-Amz-Credential"] =~ "AKIA_SYNTHETIC/"
        assert query["X-Amz-Credential"] =~ "/eu-central-1/s3/aws4_request"
        assert query["X-Amz-Signature"] =~ ~r/\A[0-9a-f]{64}\z/
        DownloadServer.hello(socket)
      end)

    path = Reader.download!(s3_config(url), %{@blob | service_name: "s3"}, temp_dir: tmp)
    assert File.read!(path) == "hello"
    Task.await(server)
  end

  test "empty S3 stream uses a fresh fallback GET and verifies its bytes", %{tmp: tmp} do
    {url, server} =
      DownloadServer.start(
        fn socket, _, index ->
          if index == 1,
            do:
              RawHTTP.reply(
                socket,
                "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
              ),
            else: DownloadServer.hello(socket)
        end,
        2
      )

    capture_log(fn ->
      path = Reader.download!(s3_config(url), %{@blob | service_name: "s3"}, temp_dir: tmp)
      assert File.read!(path) == "hello"
    end)

    Task.await(server)
  end

  test "HTTP failures are sanitized and remove partially written files", %{tmp: tmp} do
    {url, server} =
      DownloadServer.start(fn socket, _, _ ->
        RawHTTP.reply(
          socket,
          "HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        )
      end)

    error =
      assert_raise RuntimeError, fn ->
        Reader.download!(s3_config(url), %{@blob | service_name: "s3"}, temp_dir: tmp)
      end

    assert Exception.message(error) == "Import download HTTP 403"
    refute Exception.message(error) =~ "AKIA"
    assert File.ls!(tmp) == []
    Task.await(server)
  end

  test "reads stored aliases and Rails character based custom disk layout", %{
    config: config,
    tmp: tmp
  } do
    key = "éλab+%.gpx"
    dir = Path.join([config.root, "éλ", "ab"])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, key), "hello")
    config = Map.put(config, :stored_service, "historical_disk")
    blob = %{@blob | key: key, service_name: "historical_disk"}
    assert :ok = Reader.admit(config, blob)
    assert File.read!(Reader.download!(config, blob, temp_dir: tmp)) == "hello"
  end

  test "signs exact UTF8 percent plus and repeated slash S3 keys over HTTP", %{tmp: tmp} do
    for key <- ["folder/é+%/trace.gpx", "a//b///trace.gpx", "a b/trace+%.gpx", "a#b/trace.gpx"] do
      {url, server} =
        DownloadServer.start(fn socket, head, _ ->
          ["GET", target, "HTTP/1.1"] = String.split(RawHTTP.request_line(head))
          uri = URI.parse(target)
          assert URI.decode(uri.path) == "/dawarich/" <> key
          assert URI.decode_query(uri.query)["X-Amz-Signature"] =~ ~r/\A[0-9a-f]{64}\z/
          verify_signature!(uri, head)
          DownloadServer.hello(socket)
        end)

      config = Map.put(s3_config(url), :stored_service, "old_s3")

      assert File.read!(
               Reader.download!(config, %{@blob | service_name: "old_s3", key: key},
                 temp_dir: tmp
               )
             ) == "hello"

      Task.await(server)
    end
  end

  test "disk directories use Ruby characters rather than Unicode grapheme clusters", %{
    config: config,
    tmp: tmp
  } do
    key = "e\u0301abcd.gpx"
    dir = Path.join([config.root, "e\u0301", "ab"])
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, key), "hello")
    assert File.read!(Reader.download!(config, %{@blob | key: key}, temp_dir: tmp)) == "hello"
  end

  test "bounds S3 keys by UTF8 bytes and refuses invalid data before downloading", %{tmp: tmp} do
    config = s3_config("https://example.test")

    for key <- [
          "",
          String.duplicate("é", 513),
          <<255>>,
          "bad\0key",
          "../bucket/key",
          "a/../other",
          "query?token"
        ] do
      assert {:legacy, :unsafe_storage_key} =
               Reader.admit(config, %{@blob | service_name: "s3", key: key})

      assert_raise ArgumentError, ~r/key/, fn ->
        Reader.download!(config, %{@blob | service_name: "s3", key: key}, temp_dir: tmp)
      end
    end

    assert :ok =
             Reader.admit(config, %{@blob | service_name: "s3", key: String.duplicate("é", 512)})

    assert File.ls!(tmp) == []
  end

  defp verify_signature!(uri, head) do
    query = URI.decode_query(uri.query)
    [host] = RawHTTP.header(head, "host")

    canonical_query =
      query
      |> Map.delete("X-Amz-Signature")
      |> Enum.sort()
      |> Enum.map_join("&", fn {k, v} ->
        URI.encode(k, &URI.char_unreserved?/1) <> "=" <> URI.encode(v, &URI.char_unreserved?/1)
      end)

    canonical =
      Enum.join(
        ["GET", uri.path, canonical_query, "host:#{host}\n", "host", "UNSIGNED-PAYLOAD"],
        "\n"
      )

    [_access, date, region, "s3", "aws4_request"] = String.split(query["X-Amz-Credential"], "/")
    scope = Enum.join([date, region, "s3", "aws4_request"], "/")

    to_sign =
      Enum.join(
        ["AWS4-HMAC-SHA256", query["X-Amz-Date"], scope, hex(:crypto.hash(:sha256, canonical))],
        "\n"
      )

    signing_key =
      Enum.reduce([date, region, "s3", "aws4_request"], "AWS4synthetic", fn value, key ->
        :crypto.mac(:hmac, :sha256, key, value)
      end)

    assert query["X-Amz-Signature"] == hex(:crypto.mac(:hmac, :sha256, signing_key, to_sign))
  end

  defp hex(value), do: Base.encode16(value, case: :lower)

  defp s3_config(endpoint) do
    %{service: "s3"}
    |> Map.merge(
      S3.config!(%{
        "AWS_ACCESS_KEY_ID" => "AKIA_SYNTHETIC",
        "AWS_SECRET_ACCESS_KEY" => "synthetic",
        "AWS_REGION" => "eu-central-1",
        "AWS_BUCKET" => "dawarich",
        "AWS_ENDPOINT" => endpoint
      })
    )
  end
end
