defmodule Dawarich.Tracks.Reabsorber do
  @moduledoc false

  require Logger

  alias Dawarich.Tracks.{Builder, Effects, Sql, Store}

  @lookback_s 6 * 3600
  @freshness_s 60

  @pending_sql """
  SELECT EXISTS (SELECT 1 FROM points WHERE user_id = $1 AND track_id IS NULL AND anomaly IS NOT TRUE
    AND timestamp >= $2 AND created_at < $3)
  """

  @orphans_sql """
  SELECT p.id FROM points p #{Sql.device_join()}
  WHERE #{Sql.not_held_by_extraction()} AND p.user_id = $1 AND #{Sql.device()} = COALESCE($2, '')
    AND p.track_id IS NULL AND p.anomaly IS NOT TRUE AND p.timestamp BETWEEN $3 AND $4 AND p.created_at < $5
  """

  @claim_sql """
  UPDATE points p SET track_id = $1
  WHERE p.id = ANY($2::bigint[]) AND p.track_id IS NULL AND #{Sql.not_held_by_extraction()}
  """

  def call(repo, user, now) do
    fresh_before = Builder.naive(now - @freshness_s)

    if repo.query!(@pending_sql, [user.id, now - @lookback_s, fresh_before], log: false).rows == [
         [true]
       ] do
      repo
      |> Store.all(
        "SELECT #{Store.columns()} FROM tracks t WHERE t.user_id = $1 AND t.end_at >= $2 ORDER BY t.id",
        [user.id, Builder.naive(now - @lookback_s)]
      )
      |> Enum.map(&absorb(repo, user, &1, fresh_before))
      |> Enum.sum()
    else
      0
    end
  end

  defp absorb(repo, user, track, fresh_before) do
    params = [user.id, track.tracker_id, track.start_at, track.end_at, fresh_before]

    case repo.query!(@orphans_sql, params, log: false).rows |> List.flatten() do
      [] -> 0
      ids -> absorb_ids(repo, user, track, ids)
    end
  end

  defp absorb_ids(repo, user, track, ids) do
    {:ok, claimed} =
      repo.transaction(fn ->
        repo.query!("SAVEPOINT reabsorb", [], log: false)

        try do
          claimed = claim(repo, user, track, ids)
          repo.query!("RELEASE SAVEPOINT reabsorb", [], log: false)
          claimed
        rescue
          error in Postgrex.Error ->
            if error.postgres[:code] != :unique_violation, do: reraise(error, __STACKTRACE__)
            abandon(repo, user, track, ids, "unique_violation")

          Dawarich.Tracks.Invalid ->
            abandon(repo, user, track, ids, "invalid")
        end
      end)

    claimed
  end

  defp abandon(repo, user, track, ids, reason) do
    repo.query!("ROLLBACK TO SAVEPOINT reabsorb", [], log: false)
    repo.query!("RELEASE SAVEPOINT reabsorb", [], log: false)

    Logger.warning(
      "event=tracks.reabsorb_orphan_points_failed reason=#{reason} user_id=#{user.id} " <>
        "track_id=#{track.id} orphan_ids=#{Enum.join(ids, ",")}"
    )

    0
  end

  defp claim(repo, user, track, ids) do
    case repo.query!(@claim_sql, [track.id, ids], log: false).num_rows do
      0 ->
        repo.query!("ROLLBACK TO SAVEPOINT reabsorb", [], log: false)
        0

      claimed ->
        %{rows: [[min_ts, max_ts]]} =
          repo.query!(
            "SELECT MIN(timestamp), MAX(timestamp) FROM points WHERE track_id = $1",
            [track.id],
            log: false
          )

        stamps =
          if {track.start_at, track.end_at} != {min_ts, max_ts} do
            Store.save!(repo, track, start_at: min_ts, end_at: max_ts)
            [track.start_at, track.end_at, min_ts, max_ts]
          else
            {_track, changed} = Store.recalculate!(repo, track)
            if changed, do: [track.start_at, track.end_at], else: []
          end

        Effects.write!(repo, user.id, %{
          updated: if(stamps == [], do: [], else: [track.id]),
          stamps: stamps
        })

        claimed
    end
  end
end
