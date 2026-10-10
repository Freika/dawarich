defmodule Dawarich.RouteVideos.RetentionTest do
  use Dawarich.JobsCase

  alias Dawarich.RouteVideos.{Retention, Writes}

  @now ~U[2026-10-03 10:00:00Z]
  @stamp ~N[2026-10-03 10:00:00.000000]

  defmodule DeleteFailureRepo do
    defdelegate transaction(fun), to: Dawarich.ScratchRepo

    def query!(sql, params, opts \\ []) do
      if String.starts_with?(sql, "DELETE FROM route_videos"),
        do: raise("synthetic delete failure"),
        else: Dawarich.ScratchRepo.query!(sql, params, opts)
    end
  end

  setup do
    for id <- [8860, 8861] do
      ScratchRepo.insert_all("users", [
        %{
          id: id,
          email: "a8-retention-#{id}@dawarich.test",
          encrypted_password: "synthetic",
          settings: %{},
          created_at: @stamp,
          updated_at: @stamp
        }
      ])
    end

    :ok
  end

  defp video(id, attrs \\ %{}) do
    ScratchRepo.insert_all("route_videos", [
      Map.merge(
        %{
          id: id,
          user_id: 8860,
          name: "Synthetic route",
          status: 0,
          settings: %{"source" => "trip"},
          created_at: @stamp,
          updated_at: @stamp
        },
        attrs
      )
    ])

    ScratchRepo.insert_all("active_storage_blobs", [
      %{
        id: id,
        key: "a8-retention-#{id}",
        filename: "synthetic-route.mp4",
        content_type: "video/mp4",
        byte_size: 32,
        checksum: "oAK5kDPivtZCT48Age7VqQ==",
        service_name: "test",
        metadata: ~s({"identified":true,"analyzed":true}),
        created_at: @stamp
      }
    ])

    ScratchRepo.insert_all("active_storage_attachments", [
      %{
        id: id,
        name: "file",
        record_type: "RouteVideo",
        record_id: id,
        blob_id: id,
        created_at: @stamp
      }
    ])

    id
  end

  test "cap one expires oldest stored row but retains its recipe and redraw id" do
    video(886_100, %{created_at: ~N[2026-10-03 07:00:00]})
    video(886_101, %{created_at: ~N[2026-10-03 08:00:00]})
    video(886_102, %{created_at: ~N[2026-10-03 09:00:00]})
    video(886_103, %{status: 1, expired_at: ~N[2026-10-03 06:00:00]})
    assert Retention.expire_over_cap(ScratchRepo, 8860, 1, @now) == [886_101, 886_100]

    assert [
             [886_100, 1, %{"source" => "trip"}, @stamp, @stamp],
             [886_101, 1, %{"source" => "trip"}, @stamp, @stamp]
           ] =
             rows(
               "SELECT id,status,settings,expired_at,updated_at FROM route_videos WHERE id IN (886100,886101) ORDER BY id"
             )

    assert [[0]] = rows("SELECT status FROM route_videos WHERE id=886102")

    assert [[886_102], [886_103]] =
             rows("SELECT record_id FROM active_storage_attachments ORDER BY record_id")

    assert [["purge_detached", 886_101], ["purge_detached", 886_100]] =
             rows(
               "SELECT payload->>'action',(payload->>'blob_id')::bigint FROM phoenix.rails_commands ORDER BY id"
             )
  end

  test "age boundary is strict and zero disables each limit independently" do
    video(886_110, %{created_at: ~N[2026-09-03 09:59:59]})
    video(886_111, %{created_at: ~N[2026-09-03 10:00:00]})
    assert Retention.policy(%{}) == %{retention_days: 30, max_per_user: 10}

    assert Retention.policy(%{"VIDEO_RETENTION_DAYS" => "-2", "VIDEO_MAX_PER_USER" => "2_0junk"}) ==
             %{retention_days: 0, max_per_user: 20}

    assert Retention.policy(%{"VIDEO_RETENTION_DAYS" => "", "VIDEO_MAX_PER_USER" => "words"}) ==
             %{retention_days: 30, max_per_user: 0}

    assert Retention.expire_over_cap(ScratchRepo, 8860, 0, @now) == []
    assert Retention.expire_aged(ScratchRepo, 0, @now) == []
    assert Retention.expire_aged(ScratchRepo, 30, @now) == [886_110]
    assert [[0]] = rows("SELECT status FROM route_videos WHERE id=886111")
    assert Retention.run(ScratchRepo, @now, %{retention_days: 0, max_per_user: 0}) == :ok
  end

  test "equal creation stamps have the documented deterministic tie order" do
    for id <- [886_120, 886_121, 886_122], do: video(id)
    assert Retention.expire_over_cap(ScratchRepo, 8860, 1, @now) == [886_121, 886_120]
    assert [[886_122]] = rows("SELECT id FROM route_videos WHERE status=0")
  end

  test "deleting a video is owner scoped and only its file is purged" do
    video(886_130, %{user_id: 8861})
    assert {:replay, _} = Writes.destroy(ScratchRepo, 8860, 886_130, @now)
    assert [[886_130]] = rows("SELECT id FROM route_videos")
    assert rows("SELECT id FROM phoenix.rails_commands") == []
    assert {:ok, 886_130} = Writes.destroy(ScratchRepo, 8861, 886_130, @now)
    assert rows("SELECT id FROM route_videos") == []
    assert rows("SELECT id FROM active_storage_attachments") == []
    assert [[886_130]] = rows("SELECT id FROM active_storage_blobs")

    assert [[8861, 886_130]] =
             rows(
               "SELECT (payload->>'user_id')::bigint,(payload->>'blob_id')::bigint FROM phoenix.rails_commands"
             )

    assert {:replay, _} = Writes.destroy(ScratchRepo, 8861, 886_130, @now)
    assert {:replay, _} = Writes.destroy(ScratchRepo, 8861, "invalid", @now)
  end

  test "repeated expiry does not restamp an expired video" do
    video(886_140)
    assert Retention.expire(ScratchRepo, 886_140, @now) == [886_140]
    assert Retention.expire(ScratchRepo, 886_140, DateTime.add(@now, 3600)) == []

    assert [[@stamp, @stamp]] =
             rows("SELECT expired_at,updated_at FROM route_videos WHERE id=886140")

    assert [[1]] = rows("SELECT count(*) FROM phoenix.rails_commands")
  end

  test "expiry removes its attachment before command consumption" do
    video(886_150)
    assert Retention.expire(ScratchRepo, 886_150, @now) == [886_150]
    assert rows("SELECT id FROM active_storage_attachments") == []

    assert [
             [
               %{
                 "user_id" => 8860,
                 "blob_id" => 886_150,
                 "action" => "purge_detached",
                 "attachment" => %{
                   "id" => 886_150,
                   "blob_id" => 886_150,
                   "name" => "file",
                   "record_type" => "RouteVideo",
                   "record_id" => 886_150
                 }
               }
             ]
           ] =
             rows("SELECT payload FROM phoenix.rails_commands")
  end

  test "failed write transaction leaves no attachment command" do
    video(886_160)
    assert {:error, _} = Writes.destroy(DeleteFailureRepo, 8860, 886_160, @now)
    assert [[886_160]] = rows("SELECT id FROM route_videos")
    assert [[886_160]] = rows("SELECT id FROM active_storage_attachments")
    assert rows("SELECT id FROM phoenix.rails_commands") == []
  end

  test "retention age follows Rails calendar days across DST" do
    video(886_170, %{created_at: ~N[2026-10-24 10:30:00]})
    video(886_171, %{created_at: ~N[2026-10-24 09:59:59]})
    assert Retention.expire_aged(ScratchRepo, 1, ~U[2026-10-25 11:00:00Z]) == [886_171]
    assert [[0]] = rows("SELECT status FROM route_videos WHERE id=886170")
  end
end
