defmodule DawarichWeb.RouteVideoUploadTest do
  use Dawarich.DataCase, async: true

  alias Dawarich.{Accounts, Maps, RailsMessages, Uploads}
  alias Dawarich.Storage.UploadReceipts
  alias Dawarich.Test.RailsUser
  alias Dawarich.RouteVideos.Uploads, as: RouteVideoUpload

  @now ~U[2026-10-10 10:00:00.000000Z]
  @checksum "AELTPXGTbs81Ygn6v0o2PQ=="

  setup do
    id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: id, email: "video-upload-#{id}@dawarich.test"})
    %{scope: Maps.principal(Accounts.get(id), "en"), id: id}
  end

  defp attrs(overrides \\ %{}),
    do:
      Map.merge(
        %{
          "filename" => "loop.mp4",
          "content_type" => "video/mp4",
          "byte_size" => 2048,
          "checksum" => @checksum
        },
        overrides
      )

  test "native video upload target is a direct PUT for an owner-bound blob", c do
    assert {:ok, target} =
             RouteVideoUpload.target(c.scope, attrs(), "http://www.example.com", now: @now)

    assert target.url =~ "http://www.example.com/rails/active_storage/disk/"
    assert target.headers == %{"Content-Type" => "video/mp4"}
    assert {:ok, blob} = RailsMessages.verified_blob_id(target.signed_id, @now)
    assert UploadReceipts.owned?(Repo, blob, c.id)
    assert Map.keys(target) |> Enum.sort() == [:headers, :reference, :signed_id, :url]
  end

  test "native video target reserves an opaque M4 owner-bound upload", c do
    assert {:ok, target} =
             RouteVideoUpload.target(c.scope, attrs(), "http://www.example.com", now: @now)

    assert is_binary(Map.get(target, :reference))
    assert {:ok, _} = Uploads.target(c.scope, target.reference, %{})
    other_id = System.unique_integer([:positive])
    RailsUser.insert!(%{id: other_id, email: "foreign-video-#{other_id}@dawarich.test"})
    other = Maps.principal(Accounts.get(other_id), "en")
    assert {:error, :not_found} = Uploads.target(other, target.reference, %{})
    assert {:error, :not_found} = Uploads.claim(other, [target.reference], :route_video)

    assert [["route_video", "pending"]] =
             Repo.query!(
               "SELECT kind,state FROM phoenix.native_uploads WHERE reference=$1",
               [target.reference],
               log: false
             ).rows
  end

  test "native video upload target refuses other media before storage", c do
    assert {:error, :rejected} =
             RouteVideoUpload.target(
               c.scope,
               attrs(%{"content_type" => "application/zip"}),
               "http://www.example.com",
               now: @now
             )
  end
end
