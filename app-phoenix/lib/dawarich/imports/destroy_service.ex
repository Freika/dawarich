defmodule Dawarich.Imports.DestroyService do
  @moduledoc false
  alias Dawarich.Imports.{
    DestroyLease,
    DestroyExtraction,
    DestroyRemoval,
    DestroyEffects,
    LeaseLost
  }

  def call(lease) do
    state =
      DestroyLease.effect!(lease, fn ->
        case lease.repo.query!(
               "SELECT source FROM imports WHERE id=$1 AND user_id=$2",
               [lease.id, lease.user],
               log: false
             ).rows do
          [[source]] ->
            tracks =
              lease.repo.query!(
                "SELECT DISTINCT track_id FROM points WHERE import_id=$1 AND user_id=$2 AND track_id IS NOT NULL",
                [lease.id, lease.user],
                log: false
              ).rows
              |> List.flatten()

            [[context]] =
              lease.repo.query!(
                "SELECT context FROM phoenix.import_destroy_runs WHERE import_id=$1",
                [lease.id],
                log: false
              ).rows

            tracks = Enum.uniq((context["track_ids"] || []) ++ tracks)

            [[oldest]] =
              lease.repo.query!(
                "SELECT min(timestamp) FROM points WHERE import_id=$1 AND user_id=$2",
                [lease.id, lease.user],
                log: false
              ).rows

            lease.repo.query!(
              "UPDATE phoenix.import_destroy_runs SET context=context||$2 WHERE import_id=$1 AND token=$3",
              [lease.id, %{"track_ids" => tracks}, lease.token],
              log: false
            )

            %{source: source, oldest: oldest, tracks: tracks}

          [] ->
            [[context]] =
              lease.repo.query!(
                "SELECT context FROM phoenix.import_destroy_runs WHERE import_id=$1",
                [lease.id],
                log: false
              ).rows

            %{removed: true, tracks: context["track_ids"] || []}
        end
      end)

    unless Map.get(state, :removed, false) do
      DestroyEffects.status!(lease)
      DestroyExtraction.call(lease, state.source)
      deleted = delete_points(lease, 0)

      if deleted > 0 do
        DestroyLease.effect!(lease, fn ->
          lease.repo.query!(
            "UPDATE users SET points_count=coalesce(points_count,0)-$2 WHERE id=$1",
            [lease.user, deleted],
            log: false
          )
        end)

        DestroyLease.effect!(lease, fn ->
          DestroyEffects.insert!(lease, "imports.destroy_achievements", %{
            "oldest_timestamp" => state.oldest
          })
        end)
      end

      DestroyRemoval.call(lease)
    end

    orphaned_tracks(lease, state.tracks)
    DestroyEffects.finish!(lease)
    :ok
  rescue
    error in LeaseLost ->
      reraise error, __STACKTRACE__

    error ->
      fail(lease)
      reraise error, __STACKTRACE__
  end

  defp delete_points(lease, total) do
    deleted =
      DestroyLease.effect!(lease, fn ->
        rows =
          lease.repo.query!(
            "SELECT id,timestamp FROM points WHERE import_id=$1 AND user_id=$2 ORDER BY id LIMIT 5000 FOR UPDATE",
            [lease.id, lease.user],
            log: false
          ).rows

        if rows == [] do
          0
        else
          ids = Enum.map(rows, &hd/1)

          result =
            lease.repo.query!(
              "DELETE FROM points WHERE id=ANY($1::bigint[]) AND user_id=$2",
              [ids, lease.user],
              log: false
            )

          if result.num_rows > 0, do: DestroyEffects.points!(lease, Enum.map(rows, &List.last/1))
          result.num_rows
        end
      end)

    if deleted > 0, do: delete_points(lease, total + deleted), else: total
  end

  defp orphaned_tracks(_lease, []), do: :ok

  defp orphaned_tracks(lease, tracks) do
    DestroyLease.effect!(lease, fn ->
      rows =
        lease.repo.query!(
          "SELECT t.id,floor(extract(epoch FROM t.start_at))::bigint,floor(extract(epoch FROM t.end_at))::bigint FROM tracks t WHERE t.id=ANY($1::bigint[]) AND t.user_id=$2 AND NOT EXISTS(SELECT 1 FROM points p WHERE p.track_id=t.id) FOR UPDATE OF t",
          [tracks, lease.user],
          log: false
        ).rows

      if rows != [] do
        ids = Enum.map(rows, &hd/1)

        lease.repo.query!("DELETE FROM track_segments WHERE track_id=ANY($1::bigint[])", [ids],
          log: false
        )

        lease.repo.query!(
          "DELETE FROM tracks WHERE id=ANY($1::bigint[]) AND user_id=$2",
          [ids, lease.user],
          log: false
        )

        Dawarich.Tracks.Effects.write!(lease.repo, lease.user, %{
          destroyed: ids,
          stamps: Enum.flat_map(rows, fn [_id, a, b] -> [a, b] end)
        })
      end
    end)
  rescue
    error in Postgrex.Error ->
      unless error.postgres[:code] == :foreign_key_violation, do: reraise(error, __STACKTRACE__)
      :ok
  end

  defp fail(lease) do
    DestroyLease.effect!(lease, fn ->
      if lease.repo.query!(
           "UPDATE imports SET status=3,updated_at=now() WHERE id=$1 AND user_id=$2 RETURNING id",
           [lease.id, lease.user],
           log: false
         ).num_rows > 0 do
        DestroyEffects.insert!(lease, "imports.destroy_status", %{})
        Dawarich.Imports.Events.broadcast(lease.user)
      end
    end)
  rescue
    LeaseLost -> :ok
  end
end
