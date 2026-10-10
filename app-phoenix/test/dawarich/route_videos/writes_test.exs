defmodule Dawarich.RouteVideos.WritesTest do
  use Dawarich.JobsCase

  alias Dawarich.{MapGallery, RailsMessages, RouteVideos}

  @now ~U[2026-10-03 10:00:00Z]
  @stamp ~N[2026-10-03 10:00:00.000000]
  @user %{id: 8860}

  defmodule SaveFailureRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      if String.starts_with?(sql, "INSERT INTO route_videos"),
        do: raise("synthetic save failure"),
        else: Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  defmodule CapFailureRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      if String.starts_with?(sql, "UPDATE route_videos SET status"),
        do: raise("synthetic expiry status failure"),
        else: Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  setup do
    ScratchRepo.insert_all("users", [
      %{
        id: @user.id,
        email: "a8-video@dawarich.test",
        encrypted_password: "synthetic",
        settings: %{},
        created_at: @stamp,
        updated_at: @stamp
      }
    ])

    :ok
  end

  defp blob(id, attrs \\ %{}) do
    ScratchRepo.insert_all("active_storage_blobs", [
      Map.merge(
        %{
          id: id,
          key: "a8-synthetic-#{id}",
          filename: "synthetic-route.mp4",
          content_type: "video/mp4",
          byte_size: 32,
          metadata: %{"identified" => true, "analyzed" => true},
          checksum: "oAK5kDPivtZCT48Age7VqQ==",
          service_name: "test",
          created_at: @stamp
        },
        attrs
      )
      |> Map.update!(:metadata, &Jason.encode!/1)
    ])

    id
  end

  defp create(blob_id, attrs \\ %{}, repo \\ ScratchRepo, cap \\ 0) do
    params = %{
      "route_video" =>
        Map.merge(
          %{
            "file" => RailsMessages.blob_id(blob_id),
            "name" => "Saved route",
            "settings" => %{"source" => "trip"}
          },
          attrs
        )
    }

    RouteVideos.create(repo, @user, params, @now, "en", %{max_per_user: cap})
  end

  defp attach_to_owned_video(blob_id) do
    [[video]] =
      rows(
        "INSERT INTO route_videos(user_id,name,status,settings,created_at,updated_at) VALUES($1,'Existing route',0,'{}',$2,$2) RETURNING id",
        [@user.id, @stamp]
      )

    ScratchRepo.insert_all("active_storage_attachments", [
      %{
        name: "file",
        record_type: "RouteVideo",
        record_id: video,
        blob_id: blob_id,
        created_at: @stamp
      }
    ])
  end

  defp commands do
    rows("SELECT kind,payload FROM phoenix.rails_commands ORDER BY id")
  end

  test "signed MP4 at the inclusive ceiling attaches to the authenticated owner" do
    id = blob(886_000, %{byte_size: 250 * 1024 * 1024})

    attach_to_owned_video(id)

    assert {:ok, %{id: video, evicted: []}} = create(id)

    assert [[8860, "Saved route", 0, %{"source" => "trip"}, @stamp, @stamp]] =
             rows(
               "SELECT user_id,name,status,settings,created_at,updated_at FROM route_videos WHERE id=$1",
               [video]
             )

    assert [["file", "RouteVideo", ^id, @stamp]] =
             rows(
               "SELECT name,record_type,blob_id,created_at FROM active_storage_attachments WHERE record_id=$1",
               [video]
             )

    assert commands() == []

    assert %{id: ^video, files: %{"file" => %{id: ^id}}} =
             MapGallery.route_video(@user.id, video, "Europe/Berlin", ScratchRepo)

    assert MapGallery.route_video(999, video, "Europe/Berlin", ScratchRepo) == nil
  end

  test "blank name uses the localized untitled name" do
    assert {:ok, %{id: video}} = create(blob(886_001), %{"name" => "\t "})
    assert [["Untitled video"]] = rows("SELECT name FROM route_videos WHERE id=$1", [video])
  end

  test "invalid signature does not insert a video or attachment" do
    assert {:error, %{phase: :invalid_signature}} =
             create(blob(886_002), %{"file" => RailsMessages.blob_id(886_002) <> "bad"})

    assert rows("SELECT id FROM route_videos") == []
    assert rows("SELECT id FROM active_storage_attachments") == []
    assert commands() == []
  end

  test "nonvideo and oversized blob refusal queues the captured purge effect" do
    for {id, attrs} <- [
          {886_003, %{content_type: "text/plain"}},
          {886_004, %{byte_size: 250 * 1024 * 1024 + 1}}
        ] do
      assert {:error, %{phase: :rejected}} = create(blob(id, attrs))
    end

    assert rows("SELECT id FROM route_videos") == []
    assert rows("SELECT id FROM active_storage_attachments") == []

    assert commands() == [
             [
               "route_videos.attachment_job",
               %{"user_id" => 8860, "blob_id" => 886_003, "action" => "purge_unattached"}
             ],
             [
               "route_videos.attachment_job",
               %{"user_id" => 8860, "blob_id" => 886_004, "action" => "purge_unattached"}
             ]
           ]
  end

  test "pre-attach failure purges only an unattached blob" do
    id = blob(886_005)
    assert {:error, %{phase: :pre_attach}} = create(id, %{}, SaveFailureRepo)
    assert rows("SELECT id FROM route_videos") == []
    assert rows("SELECT id FROM active_storage_attachments") == []
    assert length(commands()) == 1
    rows("DELETE FROM phoenix.rails_commands")

    attach_to_owned_video(id)

    assert {:error, %{phase: :pre_attach}} = create(id, %{}, SaveFailureRepo)
    assert commands() == []
    assert [[1]] = rows("SELECT count(*) FROM active_storage_attachments")
  end

  test "post-commit cap failure retains the saved video and does not replay" do
    old_blob = blob(886_006)

    ScratchRepo.insert_all("route_videos", [
      %{
        id: 886_008,
        user_id: @user.id,
        name: "Old route",
        status: 0,
        settings: %{"source" => "trip"},
        created_at: ~N[2026-10-03 08:00:00],
        updated_at: ~N[2026-10-03 08:00:00]
      }
    ])

    ScratchRepo.insert_all("active_storage_attachments", [
      %{
        name: "file",
        record_type: "RouteVideo",
        record_id: 886_008,
        blob_id: old_blob,
        created_at: @stamp
      }
    ])

    assert {:error, %{phase: :post_commit, id: video}} =
             create(blob(886_007), %{}, CapFailureRepo, 1)

    assert [[0]] = rows("SELECT status FROM route_videos WHERE id=$1", [video])

    assert [[886_007]] =
             rows("SELECT blob_id FROM active_storage_attachments WHERE record_id=$1", [video])

    assert [[0, nil, @stamp]] =
             rows("SELECT status,expired_at,updated_at FROM route_videos WHERE id=886008")

    assert rows("SELECT id FROM active_storage_attachments WHERE record_id=886008") == []

    assert [
             [
               "route_videos.attachment_job",
               %{
                 "action" => "purge_detached",
                 "blob_id" => 886_006,
                 "user_id" => 8860,
                 "attachment" => %{
                   "record_id" => 886_008,
                   "record_type" => "RouteVideo",
                   "name" => "file",
                   "blob_id" => 886_006,
                   "id" => _
                 }
               }
             ]
           ] = commands()
  end

  test "unidentified or unanalyzed metadata replays before adoption" do
    for {id, metadata} <- [{886_009, %{}}, {886_010, %{"identified" => true}}] do
      assert {:replay, _} = create(blob(id, %{metadata: metadata}))
    end

    assert rows("SELECT id FROM route_videos") == []
    assert rows("SELECT id FROM active_storage_attachments") == []
    assert commands() == []
  end
end
