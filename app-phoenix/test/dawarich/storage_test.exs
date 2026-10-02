defmodule Dawarich.StorageTest do
  use ExUnit.Case, async: true

  alias Dawarich.Storage

  @fixture "test/fixtures/wave2/storage.json" |> File.read!() |> Jason.decode!()
  @aws %{
    "AWS_ACCESS_KEY_ID" => "AKIA",
    "AWS_SECRET_ACCESS_KEY" => "secret",
    "AWS_REGION" => "eu-central-1",
    "AWS_BUCKET" => "dawarich"
  }

  setup do
    root = Path.join(System.tmp_dir!(), "w2-storage-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{rails_root: root, config: %{service: "local", root: Path.join(root, "storage")}}
  end

  test "config!: local by default; s3 with the four AWS variables and an optional endpoint; raises on unknown, empty or incomplete configuration",
       %{rails_root: rails_root} do
    storage = Path.join(rails_root, "storage")

    assert Storage.config!(%{}, rails_root) == %{service: "local", root: storage}

    assert Storage.config!(%{"STORAGE_BACKEND" => "local"}, rails_root) ==
             %{service: "local", root: storage}

    s3 = Storage.config!(Map.put(@aws, "STORAGE_BACKEND", "s3"), rails_root)
    assert %{service: "s3", root: ^storage, bucket: "dawarich", ex_aws: ex_aws} = s3

    assert Keyword.take(ex_aws, [
             :access_key_id,
             :secret_access_key,
             :region,
             :http_client,
             :json_codec,
             :scheme,
             :host,
             :port,
             :virtual_host
           ]) == [
             access_key_id: "AKIA",
             secret_access_key: "secret",
             region: "eu-central-1",
             http_client: Dawarich.Storage.HttpcClient,
             json_codec: Jason,
             scheme: "https://",
             host: "s3.eu-central-1.amazonaws.com",
             port: 443,
             virtual_host: true
           ]

    minio =
      @aws
      |> Map.merge(%{"STORAGE_BACKEND" => "s3", "AWS_ENDPOINT" => "http://minio:9000"})
      |> Storage.config!(rails_root)

    assert Keyword.take(minio.ex_aws, [:scheme, :host, :port]) ==
             [scheme: "http://", host: "minio", port: 9000]

    preferred =
      @aws
      |> Map.merge(%{
        "STORAGE_BACKEND" => "s3",
        "AWS_ENDPOINT_URL" => "https://s3.example.test",
        "AWS_ENDPOINT" => "http://minio:9000"
      })
      |> Storage.config!(rails_root)

    assert preferred.ex_aws[:host] == "s3.example.test"

    for env <- [
          %{"STORAGE_BACKEND" => "azure"},
          %{"STORAGE_BACKEND" => ""},
          @aws |> Map.delete("AWS_BUCKET") |> Map.put("STORAGE_BACKEND", "s3"),
          @aws |> Map.put("AWS_REGION", "") |> Map.put("STORAGE_BACKEND", "s3")
        ] do
      assert_raise ArgumentError, fn -> Storage.config!(env, rails_root) end
    end
  end

  test "generate_key/0 is 28 lowercase base36 characters and 10 000 keys are distinct" do
    keys = for _ <- 1..10_000, do: Storage.generate_key()

    assert Enum.all?(keys, &(&1 =~ ~r/\A[0-9a-z]{28}\z/))
    assert keys |> Enum.uniq() |> length() == 10_000
  end

  test "disk_path/2 is root/xx/yy/key like DiskService#path_for" do
    key = "abcdefghijklmnopqrstuvwxyz01"
    assert Storage.disk_path("/r", key) == "/r/ab/cd/" <> key
  end

  test "digest_file!/1 returns base64 MD5 and size of a 12 MiB file", %{rails_root: root} do
    bin = :crypto.strong_rand_bytes(12 * 1024 * 1024)
    path = Path.join(root, "big.bin")
    File.write!(path, bin)

    assert Storage.digest_file!(path) ==
             {Base.encode64(:crypto.hash(:md5, bin)), byte_size(bin)}
  end

  test "put! local moves the file under storage/xx/yy/key and returns the blob map",
       %{rails_root: root, config: config} do
    source = Path.join(root, "export.zip")
    File.write!(source, "zip bytes")

    blob = Storage.put!(config, source, "export.json.zip", "application/zip")

    assert %{
             key: key,
             filename: "export.json.zip",
             content_type: "application/zip",
             metadata: ~s({"identified":true,"analyzed":true}),
             service_name: "local",
             byte_size: 9,
             checksum: checksum
           } = blob

    assert checksum == Base.encode64(:crypto.hash(:md5, "zip bytes"))
    assert File.read!(Storage.disk_path(config.root, key)) == "zip bytes"
    refute File.exists?(source)
  end

  test "tmp_dir!/2 is storage/.phoenix-tmp/<event> and is recreated empty", %{config: config} do
    dir = Storage.tmp_dir!(config, "evt-1")

    assert dir == Path.join([config.root, ".phoenix-tmp", "evt-1"])
    File.write!(Path.join(dir, "leftover"), "x")

    assert Storage.tmp_dir!(config, "evt-1") == dir
    assert File.ls!(dir) == []
  end

  test "sweep_tmp/2 removes only temp dirs older than the cutoff", %{config: config} do
    old = Storage.tmp_dir!(config, "old")
    fresh = Storage.tmp_dir!(config, "fresh")
    File.touch!(old, System.os_time(:second) - 90_000)

    assert Storage.sweep_tmp(config, 86_400) == :ok
    refute File.exists?(old)
    assert File.dir?(fresh)
  end

  test "content_disposition/2 matches Rails for every fixture filename" do
    for {filename, expected} <- @fixture["content_dispositions"] do
      assert Storage.content_disposition("attachment", filename) == expected, filename
    end
  end

  defmodule RangeClient do
    @moduledoc false
    @behaviour ExAws.Request.HttpClient

    @impl true
    def request(:get, _url, _body, headers, opts) do
      object = Keyword.fetch!(opts, :object)
      {_, range} = Enum.find(headers, fn {name, _} -> String.downcase(name) == "range" end)
      send(self(), {:range, range})
      [from, to] = Regex.run(~r/\Abytes=(\d+)-(\d+)\z/, range, capture: :all_but_first)
      {from, to} = {String.to_integer(from), min(String.to_integer(to), byte_size(object) - 1)}

      {:ok,
       %{
         status_code: 206,
         headers: [{"Content-Range", "bytes #{from}-#{to}/#{byte_size(object)}"}],
         body: binary_part(object, from, to - from + 1)
       }}
    end
  end

  test "download! copies a local blob; S3 assembles 8 MiB ranges", %{
    rails_root: root,
    config: config
  } do
    key = Storage.generate_key()
    File.mkdir_p!(Path.dirname(Storage.disk_path(config.root, key)))
    File.write!(Storage.disk_path(config.root, key), "local bytes")
    local = Path.join(root, "local.out")

    Storage.download!(config, key, local)
    assert File.read!(local) == "local bytes"

    object = :crypto.strong_rand_bytes(20 * 1024 * 1024)
    s3 = Storage.config!(Map.put(@aws, "STORAGE_BACKEND", "s3"), root)

    s3 = %{
      s3
      | ex_aws: Keyword.merge(s3.ex_aws, http_client: RangeClient, http_opts: [object: object])
    }

    dest = Path.join(root, "s3.out")
    Storage.download!(s3, "the-key", dest)

    assert_received {:range, "bytes=0-8388607"}
    assert_received {:range, "bytes=8388608-16777215"}
    assert_received {:range, "bytes=16777216-25165823"}
    refute_received {:range, _}
    assert File.read!(dest) == object
  end

  test "delete/2 removes a local object and ignores a missing key", %{config: config} do
    key = Storage.generate_key()
    path = Storage.disk_path(config.root, key)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "x")

    assert Storage.delete(config, key) == :ok
    refute File.exists?(path)
    assert Storage.delete(config, key) == :ok
  end

  @a12b Dawarich.Test.A12b.fixture("storage.json")

  test "sanitized_filename/1 and content_disposition/2 equal Rails', transliteration included" do
    for %{"type" => type, "filename" => name, "sanitized" => sanitized, "header" => header} <-
          @a12b["dispositions"] do
      assert Dawarich.Storage.sanitized_filename(name) == sanitized, inspect(name)
      assert Dawarich.Storage.content_disposition(type, name) == header, inspect(name)
    end
  end

  test "safe_disk_path/2 refuses what DiskService#path_for refuses" do
    root = Path.join(System.tmp_dir!(), "a12b-root")

    assert Dawarich.Storage.safe_disk_path(root, "abcdef") ==
             {:ok, Path.join([Path.expand(root), "ab", "cd", "abcdef"])}

    assert {:ok, _} =
             Dawarich.Storage.safe_disk_path(root, "raw_data_archives/1/2026/05/001.jsonl.gz.enc")

    for bad <- [
          "",
          "  ",
          "../x",
          "a/../b",
          "./a",
          "a/./b",
          "a/..",
          <<0, ?a>>,
          <<255>>,
          nil,
          "..abc"
        ],
        do: assert(Dawarich.Storage.safe_disk_path(root, bad) == :error, inspect(bad))
  end

  test "property: safe_disk_path/2 never resolves outside the root" do
    root = Path.expand(Path.join(System.tmp_dir!(), "a12b-root"))

    Dawarich.Test.A12b.seeded(fn _ ->
      key =
        Enum.map_join(1..:rand.uniform(6), "/", fn _ ->
          Enum.random(["..", ".", "a", "bc", "~", "x y", "é"])
        end)

      case Dawarich.Storage.safe_disk_path(root, key) do
        {:ok, path} -> assert String.starts_with?(path, root <> "/")
        :error -> :ok
      end
    end)
  end

  test "safe_disk_path/2 slices the folders by codepoint, as Ruby's key[0..1] does" do
    root = Path.expand(Path.join(System.tmp_dir!(), "a12b-root"))
    accent = <<?e, 0x301::utf8>>
    key = accent <> "abc"

    assert Dawarich.Storage.safe_disk_path(root, key) ==
             {:ok, Path.join([root, accent, "ab", key])}
  end

  test "services!/2 is storage.yml's registry; service!/2 and disk_service/2 resolve names as Blob#service and named_disk_service do",
       %{rails_root: rails_root} do
    test_service = %{service: "local", root: Path.join(rails_root, "tmp/storage")}
    local_service = %{service: "local", root: Path.join(rails_root, "storage")}
    s3_service = Storage.config!(Map.put(@aws, "STORAGE_BACKEND", "s3"), rails_root)
    local = Storage.services!(%{}, rails_root)

    assert local == %{
             default: "local",
             services: %{"test" => test_service, "local" => local_service}
           }

    assert Storage.services!(@aws, rails_root) == %{
             default: "local",
             services: %{"test" => test_service, "local" => local_service, "s3" => s3_service}
           }

    s3 = Storage.services!(Map.put(@aws, "STORAGE_BACKEND", "s3"), rails_root)
    assert s3.default == "s3"
    assert Storage.service!(s3, "s3") == Map.put(s3_service, :stored_service, "s3")
    assert Storage.disk_service(s3, "local") == Map.put(local_service, :stored_service, "local")
    assert Storage.disk_service(local, "gone") == Map.put(local_service, :stored_service, "local")
    assert_raise KeyError, fn -> Storage.service!(local, "s3") end
  end
end
