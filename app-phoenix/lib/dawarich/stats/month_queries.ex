defmodule Dawarich.Stats.MonthQueries do
  @moduledoc false

  alias Dawarich.Stats.ToponymRuns

  @max_speed 1_200 / 3.6
  @teleport 1_000.0
  @daily """
  WITH ordered_points AS (
    SELECT
      (to_timestamp(timestamp) AT TIME ZONE $1)::date AS local_date,
      timestamp, lonlat, import_id, snapshot_import,
      LAG(lonlat) OVER w AS prev_lonlat,
      LAG(import_id) OVER w AS prev_import_id,
      LAG(snapshot_import) OVER w AS prev_snapshot_import,
      LAG(timestamp) OVER w AS prev_timestamp
    FROM (
      SELECT points.*, COALESCE(imports.source IN (5, 7, 14, 15), FALSE) AS snapshot_import
      FROM (
        SELECT id, timestamp, lonlat, import_id FROM points
        WHERE user_id = $7 AND (anomaly = FALSE OR anomaly IS NULL) AND timestamp BETWEEN $8 AND $9
      ) AS points
      LEFT JOIN imports ON imports.id = points.import_id
    ) AS points
    WINDOW w AS (ORDER BY timestamp, id)
  ),
  measured_points AS (
    SELECT local_date, import_id, prev_import_id, snapshot_import, prev_snapshot_import,
      (timestamp - prev_timestamp) AS elapsed_seconds,
      ST_Distance(lonlat::geography, prev_lonlat::geography) AS segment_meters
    FROM ordered_points
  ),
  points_with_distances AS (
    SELECT local_date,
      CASE
        WHEN segment_meters IS NULL THEN 0
        WHEN (import_id IS NULL OR prev_import_id IS NULL OR import_id != prev_import_id
              OR snapshot_import OR prev_snapshot_import) AND elapsed_seconds > $4 THEN 0
        WHEN elapsed_seconds > 0 AND segment_meters > elapsed_seconds * $5::double precision THEN 0
        WHEN elapsed_seconds = 0 AND segment_meters > $6::double precision THEN 0
        ELSE segment_meters
      END AS segment_distance
    FROM measured_points
  )
  SELECT EXTRACT(day FROM local_date)::int, ROUND(COALESCE(SUM(segment_distance), 0))::bigint
  FROM points_with_distances
  WHERE EXTRACT(year FROM local_date) = $2::int AND EXTRACT(month FROM local_date) = $3::int
  GROUP BY local_date ORDER BY local_date
  """
  @flights """
  SELECT COALESCE(SUM(distance_km), 0)::float8 FROM flights
  WHERE user_id = $1
    AND COALESCE(flight_date, (departure_time AT TIME ZONE 'UTC' AT TIME ZONE $2)::date) BETWEEN $3 AND $4
  """
  @exists """
  SELECT EXISTS (SELECT 1 FROM points
    WHERE user_id = $1 AND (anomaly = FALSE OR anomaly IS NULL) AND timestamp BETWEEN $2 AND $3)
  """
  @local_points """
  SELECT id, timestamp, city, country_name, country_id, velocity FROM points
  WHERE user_id = $1 AND (anomaly = FALSE OR anomaly IS NULL) AND timestamp BETWEEN $2 AND $3
    AND EXTRACT(year FROM (to_timestamp(timestamp) AT TIME ZONE $4)) = $5::int
    AND EXTRACT(month FROM (to_timestamp(timestamp) AT TIME ZONE $4)) = $6::int
  ORDER BY timestamp, id
  """

  def window(year, month) do
    first = Date.new!(year, month, 1)
    start = first |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix()
    finish = first |> Date.end_of_month() |> DateTime.new!(~T[23:59:59]) |> DateTime.to_unix()
    {start - 172_800, finish + 172_800}
  end

  def exists?(repo, user_id, {start, finish}) do
    [[found]] = repo.query!(@exists, [user_id, start, finish], log: false).rows
    found
  end

  def daily(repo, user, year, month, {start, finish}) do
    params = [
      user.zone,
      year,
      month,
      user.gap_seconds,
      @max_speed,
      @teleport,
      user.id,
      start,
      finish
    ]

    days = Map.new(repo.query!(@daily, params, log: false).rows, &List.to_tuple/1)
    for day <- 1..Date.days_in_month(Date.new!(year, month, 1)), do: [day, Map.get(days, day, 0)]
  end

  def flight_distance(repo, user, year, month) do
    first = Date.new!(year, month, 1)

    [[sum]] =
      repo.query!(@flights, [user.id, user.zone, first, Date.end_of_month(first)], log: false).rows

    round(sum * 1000)
  end

  def toponyms(repo, user, year, month, {start, finish}) do
    runs = ToponymRuns.new(country_names(repo), user.min_minutes)

    repo
    |> fold(@local_points, [user.id, start, finish, user.zone, year, month], runs)
    |> ToponymRuns.result()
  end

  def country_names(repo),
    do:
      Map.new(
        repo.query!("SELECT id, name FROM countries", [], log: false).rows,
        &List.to_tuple/1
      )

  def fold(repo, sql, params, runs) do
    repo
    |> then(& &1.get_dynamic_repo())
    |> Ecto.Adapters.SQL.stream(sql, params, max_rows: 2_000, log: false)
    |> Enum.reduce(runs, fn %{rows: rows}, acc -> Enum.reduce(rows, acc, &ToponymRuns.add/2) end)
  end
end
