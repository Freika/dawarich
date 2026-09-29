defmodule Dawarich.Tracks.OrphanAttacher do
  @moduledoc false

  alias Dawarich.Tracks.{Builder, Effects, Points, Reprocessor, Settings, Sql, Store}
  alias Dawarich.Transportation.Segments

  @locked_sql """
  SELECT p.id, p.timestamp, p.track_id, p.anomaly IS TRUE, #{Sql.device_raw()},
         #{Sql.not_held_by_extraction()}
  FROM points p #{Sql.device_join()}
  WHERE p.user_id = $1 AND p.id = ANY($2::bigint[])
  ORDER BY p.id
  FOR UPDATE OF p
  """

  def call(repo, user, point, segment_points, claim_all) do
    ids = Enum.map(segment_points, & &1.id)

    with neighbor when neighbor != nil <- nearest_owned(repo, user, point, ids),
         [[track_id]] <-
           repo.query!(
             "SELECT id FROM tracks WHERE user_id = $1 AND id = $2",
             [user.id, neighbor.track_id],
             log: false
           ).rows do
      {:ok, track} =
        repo.transaction(fn -> attach(repo, user, point.id, neighbor.id, track_id, claim_all) end)

      track
    else
      _ -> nil
    end
  end

  defp nearest_owned(repo, user, point, ids) do
    repo.query!(
      "SELECT id, timestamp, track_id FROM points WHERE user_id = $1 AND id = ANY($2::bigint[]) AND track_id IS NOT NULL",
      [user.id, ids],
      log: false
    ).rows
    |> Enum.map(fn [id, timestamp, track_id] ->
      %{id: id, timestamp: timestamp, track_id: track_id}
    end)
    |> Enum.min_by(&{abs(&1.timestamp - point.timestamp), &1.id}, fn -> nil end)
  end

  defp attach(repo, user, point_id, neighbor_id, track_id, claim_all) do
    track = Store.get(repo, track_id, true)

    locked =
      repo.query!(@locked_sql, [user.id, [point_id, neighbor_id]], log: false).rows
      |> Map.new(fn [id, ts, owner, anomaly, device, claimable] ->
        {id,
         %{timestamp: ts, track_id: owner, anomaly: anomaly, device: device, claimable: claimable}}
      end)

    if attachable?(locked[point_id], locked[neighbor_id], track, user, claim_all) do
      unanchored =
        repo.query!(
          "SELECT id FROM track_segments WHERE track_id = $1 AND start_at IS NULL",
          [track.id],
          log: false
        ).rows

      Segments.anchor_now!(repo, List.flatten(unanchored))

      repo.query!(
        "UPDATE points SET track_id = $1, updated_at = now() WHERE id = $2",
        [track.id, point_id],
        log: false
      )

      refreshed = refresh(repo, user, track)

      Effects.write!(repo, user.id, %{
        updated: [track.id],
        stamps: [track.start_at, track.end_at, refreshed.start_at, refreshed.end_at]
      })

      refreshed
    end
  end

  defp attachable?(point, neighbor, track, user, claim_all) do
    point != nil and neighbor != nil and point.track_id == nil and neighbor.track_id == track.id and
      not point.anomaly and not neighbor.anomaly and to_s(point.device) == to_s(track.tracker_id) and
      to_s(neighbor.device) == to_s(point.device) and
      abs(point.timestamp - neighbor.timestamp) <= Settings.minutes_between_routes(user) * 60 and
      (claim_all or point.claimable)
  end

  defp to_s(nil), do: ""
  defp to_s(value), do: value

  defp refresh(repo, user, track) do
    points = Points.of_track(repo, track.id)
    elevation = Builder.elevation(points)

    track =
      Store.save!(repo, track,
        start_at: hd(points).timestamp,
        end_at: List.last(points).timestamp,
        elevation_gain: elevation.gain,
        elevation_loss: elevation.loss,
        elevation_min: elevation.min,
        elevation_max: elevation.max
      )

    {track, _changed} = Store.recalculate!(repo, track)
    Reprocessor.reprocess!(repo, user, track)
  end
end
