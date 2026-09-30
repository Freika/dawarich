defmodule Dawarich.Tracks.Points do
  @moduledoc false

  alias Dawarich.Tracks.Sql

  @columns "p.id, p.timestamp, ST_X(p.lonlat::geometry), ST_Y(p.lonlat::geometry), p.track_id, " <>
             "#{Sql.altitude()}, #{Sql.device_raw()}"

  @chunk_sql """
  SELECT #{@columns}
  FROM points p #{Sql.device_join()}
  WHERE p.user_id = $1 AND p.anomaly IS NOT TRUE AND p.timestamp BETWEEN $2 AND $3
    AND (NOT $4 OR p.track_id IS NULL)
    AND (CASE WHEN $5::bigint IS NULL THEN #{Sql.not_held_by_extraction()} ELSE p.import_id = $5 END)
  ORDER BY p.timestamp, p.id
  """

  @claim_sql """
  SELECT #{@columns}
  FROM points p #{Sql.device_join()}
  WHERE p.user_id = $1 AND p.id = ANY($2::bigint[]) AND p.track_id IS NULL
    AND ($3 OR #{Sql.not_held_by_extraction()})
  ORDER BY p.id
  FOR UPDATE OF p
  """

  @track_sql """
  SELECT #{@columns}
  FROM points p #{Sql.device_join()}
  WHERE p.track_id = $1
  ORDER BY p.timestamp, p.id
  """

  @realtime_sql """
  WITH points_with_gaps AS (
    SELECT
      id,
      timestamp,
      lonlat,
      tracker_id,
      LAG(lonlat) OVER (PARTITION BY tracker_id ORDER BY timestamp) as prev_lonlat,
      LAG(timestamp) OVER (PARTITION BY tracker_id ORDER BY timestamp) as prev_timestamp,
      ST_Distance(
        lonlat::geography,
        LAG(lonlat) OVER (PARTITION BY tracker_id ORDER BY timestamp)::geography
      ) as distance_meters,
      (timestamp - LAG(timestamp) OVER (PARTITION BY tracker_id ORDER BY timestamp)) as time_diff_seconds
    FROM points
    WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 AND track_id IS NULL AND (anomaly IS NOT TRUE)
  ),
  segment_breaks AS (
    SELECT *,
      CASE
        WHEN prev_lonlat IS NULL THEN 1
        WHEN time_diff_seconds > $4 THEN 1
        WHEN distance_meters > $5 THEN 1
        ELSE 0
      END as is_break
    FROM points_with_gaps
  ),
  segments AS (
    SELECT *,
      SUM(is_break) OVER (PARTITION BY tracker_id ORDER BY timestamp ROWS UNBOUNDED PRECEDING) as segment_id
    FROM segment_breaks
  )
  SELECT
    tracker_id,
    array_agg(id ORDER BY timestamp) as point_ids,
    sum(COALESCE(distance_meters, 0)) as total_distance_meters
  FROM segments
  GROUP BY tracker_id, segment_id
  HAVING count(*) >= 2
  ORDER BY tracker_id NULLS FIRST, segment_id
  """

  def realtime_segments(repo, user_id, from_ts, to_ts, minutes, meters) do
    segments = query!(repo, @realtime_sql, [user_id, from_ts, to_ts, minutes * 60, meters])

    by_id =
      repo
      |> query!(
        "SELECT #{@columns} FROM points p #{Sql.device_join()} WHERE p.id = ANY($1::bigint[])",
        [
          segments |> Enum.flat_map(&Enum.at(&1, 1))
        ]
      )
      |> Map.new(&{hd(&1), to_point(&1)})

    Enum.map(segments, fn [tracker_id, ids, meters_sum] ->
      %{
        tracker_id: tracker_id,
        points: ids |> Enum.map(&by_id[&1]) |> Enum.reject(&is_nil/1),
        distance: meters_sum * 1.0
      }
    end)
  end

  def load_chunk(repo, user_id, from_ts, to_ts, opts) do
    params = [
      user_id,
      from_ts,
      to_ts,
      opts[:untracked_only] not in [nil, false],
      opts[:import_id]
    ]

    repo |> query!(@chunk_sql, params) |> Enum.map(&to_point/1)
  end

  def claim_orphans!(repo, user_id, ids, claim_all) do
    repo
    |> query!(@claim_sql, [user_id, ids, claim_all])
    |> Enum.map(&to_point/1)
    |> Enum.sort_by(&{&1.timestamp, &1.id})
  end

  def of_track(repo, track_id),
    do: repo |> query!(@track_sql, [track_id]) |> Enum.map(&to_point/1)

  def segments(points, minutes) do
    points
    |> Enum.group_by(&(&1.tracker_id || ""))
    |> then(fn groups ->
      points |> Enum.map(&(&1.tracker_id || "")) |> Enum.uniq() |> Enum.map(&groups[&1])
    end)
    |> Enum.flat_map(&split_at_gaps(&1, minutes * 60))
  end

  defp split_at_gaps(points, gap_s) do
    points
    |> Enum.chunk_while(
      [],
      fn
        point, [] ->
          {:cont, [point]}

        point, [prev | _] = acc when point.timestamp - prev.timestamp > gap_s ->
          {:cont, Enum.reverse(acc), [point]}

        point, acc ->
          {:cont, [point | acc]}
      end,
      fn acc -> {:cont, Enum.reverse(acc), []} end
    )
    |> Enum.filter(&(length(&1) >= 2))
  end

  defp query!(repo, sql, params), do: repo.query!(sql, params, log: false).rows

  defp to_point([id, timestamp, lon, lat, track_id, altitude, tracker_id]) do
    %{
      id: id,
      timestamp: timestamp,
      lon: lon,
      lat: lat,
      track_id: track_id,
      altitude: altitude,
      tracker_id: tracker_id
    }
  end
end
