defmodule Dawarich.Trips.Queries do
  @moduledoc false

  @device "COALESCE(CASE WHEN points.source_id IS NULL THEN points.tracker_id ELSE point_sources.tracker_id END, '')"
  @from """
  FROM points LEFT JOIN point_sources ON point_sources.id = points.source_id
  WHERE points.user_id = $1 AND (points.anomaly IS NULL OR points.anomaly = false)
    AND points.timestamp BETWEEN $2 AND $3
  """
  @primary """
  AND ($4::text[] IS NULL OR EXISTS (
    SELECT 1 FROM unnest($4::text[], $5::bigint[], $6::bigint[]) AS w(tracker_id, start_at, end_at)
    WHERE w.tracker_id = #{@device} AND points.timestamp BETWEEN w.start_at AND w.end_at))
  """

  def trip(repo, id) do
    case query(
           repo,
           "SELECT t.user_id, t.started_at, t.ended_at, t.path IS NULL, u.settings FROM trips t JOIN users u ON u.id = t.user_id WHERE t.id = $1",
           [id]
         ) do
      [[user_id, started_at, ended_at, path_blank, settings]] ->
        %{
          id: id,
          user_id: user_id,
          started_at: started_at,
          ended_at: ended_at,
          path_blank: path_blank,
          settings: Dawarich.UserSettings.safe(settings),
          from: epoch(started_at),
          to: epoch(ended_at)
        }

      [] ->
        nil
    end
  end

  def device_windows(repo, trip, gap_seconds) do
    query(
      repo,
      """
      WITH ordered_points AS (
        SELECT id, timestamp, tracker_id,
          LAG(timestamp) OVER (PARTITION BY tracker_id ORDER BY timestamp, id) AS previous_timestamp
        FROM (SELECT points.id, points.timestamp, #{@device} AS tracker_id #{@from}) AS recordings
      ), sessions AS (
        SELECT timestamp, tracker_id,
          SUM(CASE WHEN previous_timestamp IS NULL OR timestamp - previous_timestamp > $4 THEN 1 ELSE 0 END)
            OVER (PARTITION BY tracker_id ORDER BY timestamp, id ROWS UNBOUNDED PRECEDING) AS session_number
        FROM ordered_points
      )
      SELECT tracker_id, MIN(timestamp), MAX(timestamp)
      FROM sessions
      GROUP BY tracker_id, session_number
      ORDER BY SUM(COUNT(*)) OVER (PARTITION BY tracker_id) DESC, NULLIF(tracker_id, '') NULLS LAST, MIN(timestamp)
      """,
      [trip.user_id, trip.from, trip.to, gap_seconds]
    )
  end

  def coordinates(repo, trip, windows) do
    query(
      repo,
      "SELECT ST_X(points.lonlat::geometry), ST_Y(points.lonlat::geometry) #{@from} #{@primary} ORDER BY points.timestamp",
      [trip.user_id, trip.from, trip.to | window_params(windows)]
    )
  end

  def day_stats(repo, trip, windows, zone) do
    repo
    |> query(
      """
      SELECT (to_timestamp(points.timestamp) AT TIME ZONE $7)::date,
             to_char(to_timestamp(MIN(points.timestamp)) AT TIME ZONE $7, 'YYYY-MM-DD"T"HH24:MI:SS'),
             to_char(to_timestamp(MAX(points.timestamp)) AT TIME ZONE $7, 'YYYY-MM-DD"T"HH24:MI:SS'),
             COALESCE(ST_Length(ST_MakeLine(points.lonlat::geometry ORDER BY points.timestamp)::geography), 0)
      #{@from} #{@primary}
      GROUP BY 1
      """,
      [trip.user_id, trip.from, trip.to | window_params(windows)] ++ [zone]
    )
    |> Map.new(fn [day, first, last, meters] ->
      {day,
       %{
         first: NaiveDateTime.from_iso8601!(first),
         last: NaiveDateTime.from_iso8601!(last),
         distance_m: meters
       }}
    end)
  end

  def distance_meters(repo, trip, windows) do
    [[meters]] =
      query(
        repo,
        """
        WITH points_with_previous AS (
          SELECT points.lonlat, LAG(points.lonlat) OVER (ORDER BY points.timestamp) AS prev_lonlat
          #{@from} #{@primary}
        )
        SELECT COALESCE(SUM(ST_Distance(lonlat::geography, prev_lonlat::geography)), 0)::float8
        FROM points_with_previous WHERE prev_lonlat IS NOT NULL
        """,
        [trip.user_id, trip.from, trip.to | window_params(windows)]
      )

    meters
  end

  def country_names(repo, trip) do
    repo
    |> query("SELECT points.country_name #{@from} ORDER BY points.timestamp", [
      trip.user_id,
      trip.from,
      trip.to
    ])
    |> Enum.map(&hd/1)
  end

  def lock(repo, trip) do
    case query(repo, "SELECT started_at, ended_at FROM trips WHERE id = $1 FOR UPDATE", [trip.id]) do
      [] ->
        :missing

      [[started_at, ended_at]] ->
        if {started_at, ended_at} == {trip.started_at, trip.ended_at}, do: :ok, else: :superseded
    end
  end

  def write_path(repo, trip, wkt) do
    query(
      repo,
      "UPDATE trips SET path = ST_GeomFromText($2, 4326), updated_at = $3 WHERE id = $1 AND path IS DISTINCT FROM ST_GeomFromText($2, 4326)",
      [trip.id, wkt, NaiveDateTime.utc_now()]
    )
  end

  def write_distance(repo, trip, distance) do
    query(
      repo,
      "UPDATE trips SET distance = $2, updated_at = $3 WHERE id = $1 AND distance IS DISTINCT FROM $2",
      [trip.id, distance, NaiveDateTime.utc_now()]
    )
  end

  def write_countries(repo, trip, countries) do
    query(
      repo,
      "UPDATE trips SET visited_countries = $2, updated_at = $3 WHERE id = $1 AND visited_countries IS DISTINCT FROM $2",
      [trip.id, countries, NaiveDateTime.utc_now()]
    )
  end

  def clear_cooldown(repo, trip_id) do
    query(
      repo,
      "UPDATE trips SET last_recalculated_at = NULL WHERE id = $1 AND last_recalculated_at IS NOT NULL",
      [trip_id]
    )
  end

  def event!(repo, trip_id, kind, unit, failed \\ false) do
    query(
      repo,
      "INSERT INTO phoenix.trip_events (trip_id, kind, distance_unit, failed, created_at) SELECT $1, $2, $3, $4, $5 WHERE EXISTS (SELECT 1 FROM trips WHERE id = $1)",
      [trip_id, kind, unit, failed, DateTime.utc_now()]
    )

    :ok
  end

  defp window_params(nil), do: [nil, nil, nil]

  defp window_params(windows) do
    Enum.reduce(Enum.reverse(windows), [[], [], []], fn {tracker, first, last},
                                                        [trackers, starts, ends] ->
      [[tracker | trackers], [first | starts], [last | ends]]
    end)
  end

  defp epoch(%NaiveDateTime{} = value),
    do: value |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp query(repo, sql, params), do: repo.query!(sql, params, log: false).rows
end
