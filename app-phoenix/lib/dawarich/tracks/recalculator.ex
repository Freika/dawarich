defmodule Dawarich.Tracks.Recalculator do
  @moduledoc false

  alias Dawarich.{Geo, RubyFloat}
  alias Dawarich.Tracks.{Builder, Destroy, Effects, Store}

  @snapshot_sql """
  SELECT id, timestamp, ST_X(lonlat::geometry), ST_Y(lonlat::geometry)
  FROM points
  WHERE track_id = $1 AND anomaly IS NOT TRUE
  ORDER BY timestamp ASC, id ASC
  """

  @segments_sql """
  SELECT id, floor(extract(epoch FROM start_at))::bigint, floor(extract(epoch FROM end_at))::bigint,
         start_index, end_index
  FROM track_segments WHERE track_id = $1 ORDER BY id
  """

  @segment_update_sql """
  UPDATE track_segments SET path = ST_GeomFromText($2, 4326), distance = $3, duration = $4, avg_speed = $5,
    max_speed = $6, updated_at = now()
  WHERE id = $1 AND (path IS DISTINCT FROM ST_GeomFromText($2, 4326) OR distance IS DISTINCT FROM $3
    OR duration IS DISTINCT FROM $4 OR avg_speed IS DISTINCT FROM $5 OR max_speed IS DISTINCT FROM $6)
  """

  def run(repo, track_id) do
    {:ok, outcome} =
      repo.transaction(fn ->
        with track when track != nil <- Store.get(repo, track_id),
             [[count]] when count >= 2 <-
               repo.query!("SELECT count(*) FROM points WHERE track_id = $1", [track_id],
                 log: false
               ).rows do
          {:recalculated, call(repo, track)}
        else
          nil ->
            :missing

          [[_count]] ->
            Destroy.destroy!(repo, Store.get(repo, track_id).user_id, [track_id])
            :destroyed
        end
      end)

    outcome
  end

  def call(repo, track) do
    points =
      repo.query!(@snapshot_sql, [track.id], log: false).rows
      |> Enum.map(fn [id, ts, lon, lat] -> %{id: id, timestamp: ts, lon: lon, lat: lat} end)

    if length(points) < 2, do: raise(Dawarich.Tracks.Invalid)

    distance = RubyFloat.round(distance(points) * 1.0)
    duration = List.last(points).timestamp - hd(points).timestamp

    attrs = [
      original_path: Builder.path_wkt(points),
      distance: distance,
      duration: duration,
      avg_speed: Builder.avg_speed_kmh(distance, duration)
    ]

    Store.update_if_changed!(repo, track.id, attrs)

    Effects.write!(repo, track.user_id, %{
      updated: [track.id],
      stamps: [track.start_at, track.end_at]
    })

    repo.query!(@segments_sql, [track.id], log: false).rows
    |> Enum.each(&update_segment(repo, &1, points))

    Map.merge(track, Map.new(attrs))
  end

  defp update_segment(repo, [id, start_at, end_at, start_index, end_index], points) do
    segment_points =
      if start_at && end_at,
        do: Enum.filter(points, &(&1.timestamp >= start_at and &1.timestamp <= end_at)),
        else: Enum.slice(points, (start_index || 0)..(end_index || 0)//1)

    distance = segment_points |> distance() |> Kernel.*(1.0) |> RubyFloat.round()
    duration = segment_duration(start_at, end_at, segment_points)
    path = if length(segment_points) >= 2, do: Builder.path_wkt(segment_points)

    repo.query!(
      @segment_update_sql,
      [
        id,
        path,
        distance,
        duration,
        Builder.avg_speed_kmh(distance, duration),
        Enum.max(pair_speeds(segment_points), fn -> 0.0 end)
      ],
      log: false
    )
  end

  defp segment_duration(start_at, end_at, _points) when start_at != nil and end_at != nil,
    do: end_at - start_at

  defp segment_duration(_start_at, _end_at, points) when length(points) < 2, do: 0

  defp segment_duration(_start_at, _end_at, points),
    do: List.last(points).timestamp - hd(points).timestamp

  def distance(points), do: points |> pairs() |> Enum.map(&pair_distance/1) |> RubyFloat.sum()

  defp pair_speeds(points) do
    for {a, b} = pair <- pairs(points),
        b.timestamp - a.timestamp > 0,
        do: pair_distance(pair) / (b.timestamp - a.timestamp) * 3.6
  end

  defp pairs(points), do: Enum.zip(points, Enum.drop(points, 1))

  defp pair_distance({a, b}), do: Geo.distance_m({a.lat, a.lon}, {b.lat, b.lon})
end
