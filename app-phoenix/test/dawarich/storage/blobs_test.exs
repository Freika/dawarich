defmodule Dawarich.Storage.BlobsTest do
  use Dawarich.IngestCase

  alias Dawarich.Storage.Blobs
  alias Dawarich.Test.A12b

  @fx A12b.fixture("storage.json")
  @attrs ~w(id key filename content_type metadata service_name byte_size checksum)

  defp attrs(blob),
    do:
      blob.pairs
      |> Map.new()
      |> Map.take(@attrs)
      |> Map.update!("metadata", &Jason.decode!(&1 || "{}"))

  test "create_before_direct_upload/4 writes the row Rails wrote for the same request" do
    rails = @fx["direct_upload"]["row"]
    Repo.query!("SELECT setval('active_storage_blobs_id_seq', 970599)")
    [ok | _] = @fx["upload_requests"]
    params = ok["body"] |> Base.decode64!() |> Jason.decode!() |> Map.fetch!("blob")

    {:ok, blob} =
      Blobs.create_before_direct_upload(
        %{service: "local", stored_service: "test"},
        params,
        ~N[2026-10-02 12:00:00.000000],
        key: fn -> rails["key"] end,
        zone: @fx["direct_upload"]["time_zone"]
      )

    assert attrs(blob) == Map.take(rails, @attrs)

    assert Jason.decode!(ok["response_body"] |> Base.decode64!())["created_at"] ==
             blob.created_at_json
  end

  test "drops Active Storage's protected metadata keys, keeps the rest" do
    {:ok, blob} =
      Blobs.create_before_direct_upload(
        %{service: "local"},
        %{
          "filename" => "a",
          "byte_size" => 1,
          "checksum" => "x",
          "metadata" => %{
            "identified" => true,
            "analyzed" => true,
            "composed" => true,
            "custom" => %{"a" => 1}
          }
        },
        ~N[2026-10-02 12:00:00],
        zone: "Etc/UTC"
      )

    assert Jason.decode!(blob.metadata) == %{"custom" => %{"a" => 1}}
    assert Blobs.find(blob.id).key == blob.key
    assert Blobs.find(-1) == nil
  end
end
