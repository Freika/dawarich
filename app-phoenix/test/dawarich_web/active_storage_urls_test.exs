defmodule DawarichWeb.ActiveStorageUrlsTest do
  use ExUnit.Case, async: true

  alias Dawarich.Storage
  alias Dawarich.Test.A12b
  alias DawarichWeb.ActiveStorageUrls

  @fx A12b.fixture("storage.json")
  @base "http://dawarich.example"
  @local %{service: "local", root: "/unused", stored_service: "test"}

  defp blob(id) do
    row = Enum.find(@fx["blobs"], &(&1["id"] == id))

    %{
      id: row["id"],
      key: row["key"],
      filename: row["filename"],
      content_type: row["content_type"],
      service_name: row["service_name"],
      byte_size: row["byte_size"],
      checksum: row["checksum"]
    }
  end

  defp s3(label) do
    env = %{
      "STORAGE_BACKEND" => "s3",
      "AWS_ACCESS_KEY_ID" => String.duplicate("a", 20),
      "AWS_SECRET_ACCESS_KEY" => String.duplicate("b", 40),
      "AWS_REGION" => "eu-central-1",
      "AWS_BUCKET" => "dawarich-a12b"
    }

    endpoint =
      %{"aws" => nil, "custom" => "https://minio.example:9000", "ip" => "http://127.0.0.1:9000"}[
        label
      ]

    Storage.config!(
      if(endpoint, do: Map.put(env, "AWS_ENDPOINT_URL", endpoint), else: env),
      "/unused"
    )
  end

  defp parts(url) do
    uri = URI.parse(url)
    {uri.scheme, uri.host, uri.port, uri.path, URI.decode_query(uri.query || "")}
  end

  test "the serving rules are Rails' lists" do
    assert ActiveStorageUrls.binary_types() == @fx["settings"]["binary_content_types"]
    assert ActiveStorageUrls.inline_types() == @fx["settings"]["inline_content_types"]
  end

  test "disk service URLs equal Rails' blob.url for every blob and disposition" do
    for %{"blob_id" => id, "disposition" => d, "disk_url" => url} <- @fx["urls"],
        do:
          assert(
            ActiveStorageUrls.service_url(@local, blob(id), d, @base, A12b.now()) == url,
            "#{id} #{inspect(d)}"
          )
  end

  test "S3 presigned GETs carry Rails' host, path, query and signature on AWS, a custom endpoint and an IP endpoint" do
    for %{"blob_id" => id, "disposition" => d, "s3" => urls} <- @fx["urls"],
        {label, url} <- urls,
        do:
          assert(
            parts(ActiveStorageUrls.service_url(s3(label), blob(id), d, @base, A12b.now())) ==
              parts(url),
            "#{id} #{label} #{inspect(d)}"
          )
  end

  test "direct-upload targets and headers equal Rails' for disk and S3" do
    for %{"blob_id" => id, "disk" => disk, "s3" => s3_targets} <- @fx["direct_uploads"] do
      {url, headers} = ActiveStorageUrls.direct_upload(@local, blob(id), @base, A12b.now())
      assert url == disk["url"]
      assert Jason.decode!(Jason.encode!(headers)) == disk["headers"]

      for {label, target} <- s3_targets do
        {url, headers} = ActiveStorageUrls.direct_upload(s3(label), blob(id), @base, A12b.now())
        assert parts(url) == parts(target["url"]), "#{id} #{label}"
        assert Jason.decode!(Jason.encode!(headers)) == target["headers"], "#{id} #{label}"
      end
    end
  end
end
