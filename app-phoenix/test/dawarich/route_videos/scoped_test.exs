defmodule Dawarich.RouteVideos.ScopedTest do
  use Dawarich.DataCase, async: true

  alias Dawarich.{Accounts, Maps, RailsMessages, RouteVideos}
  alias Dawarich.Jobs.Ownership
  alias Dawarich.Storage.UploadReceipts
  alias Dawarich.Test.RailsUser

  @now ~U[2026-10-10 10:00:00.000000Z]
  @checksum "AELTPXGTbs81Ygn6v0o2PQ=="
  @policy %{max_per_user: 2}

  setup do
    Ownership.put!(Repo, "cron:route_videos_purge_job", :oban)
    [actor, other] = for _ <- 1..2, do: account!()
    %{scope: Maps.principal(actor, "en"), other: Maps.principal(other, "en"), actor: actor}
  end

  defp account! do
    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "route-video-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    Accounts.get(id)
  end

  defp attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "filename" => "leipzig-loop.mp4",
        "content_type" => "video/mp4",
        "byte_size" => 4096,
        "checksum" => @checksum
      },
      overrides
    )
  end

  defp reserve!(scope, overrides \\ %{}) do
    {:ok, blob} = RouteVideos.reserve_upload(scope, attrs(overrides), now: @now)
    RailsMessages.blob_id(blob.id)
  end

  defp save(scope, signed, name \\ "Leipzig loop") do
    RouteVideos.create_video(
      scope,
      %{"signed_id" => signed, "name" => name, "settings" => %{"format" => "square"}},
      now: @now,
      policy: @policy
    )
  end

  defp videos(user), do: rows("SELECT count(*) FROM route_videos WHERE user_id=$1", [user])

  defp purges(blob),
    do:
      rows(
        "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.Exports.PurgeWorker' AND args->'blob_ids' @> to_jsonb($1::bigint)",
        [blob]
      )

  defp analyses(blob),
    do:
      rows(
        "SELECT count(*) FROM oban.oban_jobs WHERE worker='Dawarich.RouteVideos.AnalysisWorker' AND (args->>'blob_id')::bigint=$1",
        [blob]
      )

  defp blob_id(signed), do: elem(RailsMessages.verified_blob_id(signed, @now), 1)

  defp video!(user, name, stamp) do
    [[id]] =
      rows(
        "INSERT INTO route_videos(user_id,name,status,settings,created_at,updated_at) VALUES($1,$2,0,'{}',$3,$3) RETURNING id",
        [user, name, stamp]
      )

    id
  end

  test "reserved uploads are bound to the actor and limited to MP4 video", c do
    signed = reserve!(c.scope)
    assert UploadReceipts.owned?(Repo, blob_id(signed), c.actor.id)

    assert [["leipzig-loop.mp4", 4096, @checksum, "video/mp4"]] =
             rows(
               "SELECT filename,byte_size,checksum,content_type FROM active_storage_blobs WHERE id=$1",
               [blob_id(signed)]
             )
  end

  test "foreign upload reference cannot attach", c do
    foreign = reserve!(c.other)
    assert {:error, :foreign_upload} = save(c.scope, foreign)
    assert videos(c.actor.id) == [[0]]
    assert purges(blob_id(foreign)) == [[0]]

    [[legacy]] =
      rows(
        "INSERT INTO active_storage_blobs(key,filename,content_type,metadata,service_name,byte_size,checksum,created_at) VALUES('legacy-route','a.mp4','video/mp4',NULL,'test',32,$1,$2) RETURNING id",
        [@checksum, DateTime.to_naive(@now)]
      )

    assert {:error, :foreign_upload} = save(c.scope, RailsMessages.blob_id(legacy))
    assert {:error, :foreign_upload} = save(c.scope, RailsMessages.blob_id(legacy) <> "x")
    assert videos(c.actor.id) == [[0]]
  end

  test "wrong media or oversized video refuses without orphaned attachment", c do
    before = rows("SELECT count(*) FROM active_storage_blobs")

    assert {:error, :rejected} =
             RouteVideos.reserve_upload(c.scope, attrs(%{"content_type" => "video/webm"}),
               now: @now
             )

    assert {:error, :rejected} =
             RouteVideos.reserve_upload(
               c.scope,
               attrs(%{"byte_size" => 250 * 1024 * 1024 + 1}),
               now: @now
             )

    assert {:error, :rejected} =
             RouteVideos.reserve_upload(c.scope, attrs(%{"checksum" => ""}), now: @now)

    assert rows("SELECT count(*) FROM active_storage_blobs") == before

    signed = reserve!(c.scope)
    blob = blob_id(signed)
    rows("UPDATE active_storage_blobs SET content_type='video/webm' WHERE id=$1", [blob])
    assert {:error, :rejected} = save(c.scope, signed)
    assert videos(c.actor.id) == [[0]]

    assert rows("SELECT count(*) FROM active_storage_attachments WHERE blob_id=$1", [blob]) == [
             [0]
           ]

    assert purges(blob) == [[1]]
  end

  test "cancel before finalize leaves no gallery row", c do
    signed = reserve!(c.scope)
    blob = blob_id(signed)
    assert :ok = RouteVideos.discard_upload(c.scope, signed, now: @now)
    assert :ok = RouteVideos.discard_upload(c.scope, signed, now: @now)
    assert purges(blob) == [[1]]
    assert {:error, :invalid_upload} = save(c.scope, signed)
    assert videos(c.actor.id) == [[0]]

    foreign = reserve!(c.other)
    assert {:error, :foreign_upload} = RouteVideos.discard_upload(c.scope, foreign, now: @now)
    assert purges(blob_id(foreign)) == [[0]]
  end

  test "retention evicts in original order and analysis publishes once", c do
    oldest = video!(c.actor.id, "oldest", ~N[2026-10-01 08:00:00])
    older = video!(c.actor.id, "older", ~N[2026-10-02 08:00:00])
    newer = video!(c.actor.id, "newer", ~N[2026-10-03 08:00:00])
    signed = reserve!(c.scope)

    assert {:ok, %{id: id, evicted: [^older, ^oldest]}} = save(c.scope, signed)

    assert rows("SELECT id,status FROM route_videos WHERE user_id=$1 ORDER BY id", [c.actor.id]) ==
             Enum.sort([[oldest, 1], [older, 1], [newer, 0], [id, 0]])

    assert [["Leipzig loop", %{"format" => "square"}]] =
             rows("SELECT name,settings FROM route_videos WHERE id=$1", [id])

    assert analyses(blob_id(signed)) == [[1]]
    assert {:error, :invalid_upload} = save(c.scope, signed, "again")
    assert analyses(blob_id(signed)) == [[1]]
    assert videos(c.actor.id) == [[4]]
  end

  test "revoked actor cannot reserve, attach, discard or delete", c do
    signed = reserve!(c.scope)
    {:ok, %{id: id}} = save(c.scope, signed)
    other = reserve!(c.scope)

    rows("UPDATE users SET encrypted_password=$2 WHERE id=$1", [
      c.actor.id,
      String.duplicate("z", 60)
    ])

    assert {:error, :stale_session} = RouteVideos.reserve_upload(c.scope, attrs(), now: @now)
    assert {:error, :stale_session} = save(c.scope, other)
    assert {:error, :stale_session} = RouteVideos.discard_upload(c.scope, other, now: @now)
    assert {:error, :stale_session} = RouteVideos.destroy_video(c.scope, id, now: @now)
    assert videos(c.actor.id) == [[1]]
    assert purges(blob_id(other)) == [[0]]
  end

  test "video delete is owner scoped and detaches the stored file", c do
    signed = reserve!(c.scope)
    {:ok, %{id: id}} = save(c.scope, signed)

    assert {:error, :not_found} = RouteVideos.destroy_video(c.other, id, now: @now)
    assert videos(c.actor.id) == [[1]]
    assert {:ok, ^id} = RouteVideos.destroy_video(c.scope, id, now: @now)
    assert videos(c.actor.id) == [[0]]
    assert purges(blob_id(signed)) == [[1]]
    assert {:error, :not_found} = RouteVideos.destroy_video(c.scope, id, now: @now)
    assert {:error, :not_found} = RouteVideos.destroy_video(c.scope, "nope", now: @now)
  end
end
