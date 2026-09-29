defmodule Dawarich.Tracks.Merger do
  @moduledoc false

  require Logger

  alias Dawarich.Tracks.{Builder, Destroy, Effects, Settings, Store}
  alias Dawarich.Transportation.Segments

  @preceding_sql """
  SELECT #{Store.columns()} FROM tracks t
  WHERE t.user_id = $1 AND t.tracker_id IS NOT DISTINCT FROM $2
    AND t.end_at < (to_timestamp($3::bigint) AT TIME ZONE 'UTC')
    AND t.end_at > (to_timestamp($3::bigint - $4) AT TIME ZONE 'UTC')
    AND t.id <> $5
  ORDER BY t.end_at DESC
  LIMIT 1
  """

  def merge_into_preceding(repo, user, track) do
    params = [
      user.id,
      track.tracker_id,
      track.start_at,
      Settings.minutes_between_routes(user) * 60,
      track.id
    ]

    case Store.all(repo, @preceding_sql, params) do
      [preceding] -> call(repo, user, preceding, track)
      [] -> false
    end
  end

  def call(_repo, _user, older, newer)
      when is_nil(older) or is_nil(newer) or older.id == newer.id,
      do: false

  def call(repo, user, older, newer) do
    case merge(repo, user, older, newer) do
      {:ok, merged} ->
        detect_after_merge(repo, user, merged)
        true

      :error ->
        false
    end
  end

  defp merge(repo, user, older, newer) do
    repo.transaction(fn -> absorb(repo, user, older, newer) end)
  rescue
    error in Postgrex.Error ->
      if error.postgres[:code] == :unique_violation,
        do:
          Logger.info(
            "event=tracks.unique_violation_rescued service=merger user_id=#{user.id} " <>
              "older_track_id=#{older.id} newer_track_id=#{newer.id}"
          ),
        else: merge_failed(older, newer, error)

      :error

    error ->
      merge_failed(older, newer, error)
      :error
  end

  defp merge_failed(older, newer, error),
    do:
      Logger.error(
        "Failed to merge tracks #{older.id} and #{newer.id}: #{Exception.message(error)}"
      )

  defp detect_after_merge(repo, user, merged) do
    Builder.detect_after_commit(repo, user, merged)
  rescue
    error ->
      Logger.error(
        "Failed to detect segments after merging tracks #{merged.id}: #{Exception.message(error)}"
      )

      :ok
  end

  defp absorb(repo, user, older, newer) do
    Segments.clear_inference!(repo, older.id)
    Segments.clear_inference!(repo, newer.id)

    repo.query!(
      "UPDATE track_segments SET track_id = $1 WHERE track_id = $2 AND start_at IS NOT NULL",
      [older.id, newer.id],
      log: false
    )

    repo.query!("DELETE FROM track_segments WHERE track_id = $1", [newer.id], log: false)

    repo.query!("UPDATE points SET track_id = $1 WHERE track_id = $2", [older.id, newer.id],
      log: false
    )

    saved = Store.save!(repo, older, end_at: newer.end_at)
    {saved, _changed} = Store.recalculate!(repo, saved)
    Destroy.destroy!(repo, user.id, [newer.id])

    Effects.write!(repo, user.id, %{
      updated: [older.id],
      stamps: [older.start_at, older.end_at, saved.start_at, saved.end_at]
    })

    saved
  end
end
