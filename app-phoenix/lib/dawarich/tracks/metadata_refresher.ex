defmodule Dawarich.Tracks.MetadataRefresher do
  @moduledoc false

  require Logger

  alias Dawarich.Tracks.{Builder, Effects, Reprocessor, Store}

  @mismatched_sql """
  SELECT #{Store.columns()} FROM tracks t
  WHERE t.user_id = $1 AND (
    EXTRACT(EPOCH FROM t.start_at) <> (
      SELECT timestamp FROM points WHERE track_id = t.id ORDER BY timestamp ASC LIMIT 1
    ) OR EXTRACT(EPOCH FROM t.end_at) <> (
      SELECT timestamp FROM points WHERE track_id = t.id ORDER BY timestamp DESC LIMIT 1
    ))
  ORDER BY t.id
  """

  @points_sql "SELECT id, timestamp, altitude FROM points WHERE track_id = $1 ORDER BY id FOR UPDATE"

  def run(repo, user) do
    result =
      repo
      |> Store.all(@mismatched_sql, [user.id])
      |> Enum.reduce(%{refreshed: 0, skipped: 0, reasons: [], sample_ids: []}, fn track, acc ->
        case refresh(repo, user, track.id) do
          :unchanged -> acc
          :refreshed -> %{acc | refreshed: acc.refreshed + 1}
          reason -> skip(acc, reason, track.id)
        end
      end)

    if result.skipped > 0 do
      json = Jason.encode!(%{result | reasons: Jason.OrderedObject.new(result.reasons)})
      Logger.warning("event=tracks.metadata_refresh_incomplete user_id=#{user.id} result=#{json}")
    end

    result
  end

  defp skip(acc, reason, id) do
    reasons =
      case List.keyfind(acc.reasons, reason, 0) do
        {^reason, count} -> List.keyreplace(acc.reasons, reason, 0, {reason, count + 1})
        nil -> acc.reasons ++ [{reason, 1}]
      end

    sample_ids = if length(acc.sample_ids) < 10, do: acc.sample_ids ++ [id], else: acc.sample_ids
    %{acc | skipped: acc.skipped + 1, reasons: reasons, sample_ids: sample_ids}
  end

  defp refresh(repo, user, track_id) do
    {:ok, outcome} =
      repo.transaction(fn -> refresh_locked(repo, user, Store.get(repo, track_id, true)) end)

    outcome
  rescue
    error in Postgrex.Error ->
      if error.postgres[:constraint] == "index_tracks_on_user_tracker_start_end_unique",
        do: :bounds_collision,
        else: reraise(error, __STACKTRACE__)
  end

  defp refresh_locked(repo, user, track) do
    points =
      repo.query!(@points_sql, [track.id], log: false).rows
      |> Enum.map(fn [id, timestamp, altitude] ->
        %{id: id, timestamp: timestamp, altitude: altitude}
      end)
      |> Enum.sort_by(& &1.timestamp)

    cond do
      length(points) < 2 ->
        :insufficient_points

      {hd(points).timestamp, List.last(points).timestamp} == {track.start_at, track.end_at} ->
        :unchanged

      true ->
        elevation = Builder.elevation(points)
        start_at = hd(points).timestamp
        end_at = List.last(points).timestamp

        saved =
          Store.save!(repo, track,
            start_at: start_at,
            end_at: end_at,
            elevation_gain: elevation.gain,
            elevation_loss: elevation.loss,
            elevation_min: elevation.min,
            elevation_max: elevation.max
          )

        Reprocessor.reprocess!(repo, user, saved)

        Effects.write!(repo, user.id, %{
          updated: [track.id],
          stamps: [track.start_at, track.end_at, start_at, end_at]
        })

        :refreshed
    end
  end
end
