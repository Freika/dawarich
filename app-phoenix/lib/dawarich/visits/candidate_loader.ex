defmodule Dawarich.Visits.CandidateLoader do
  @moduledoc false

  require Logger

  @max_candidate_points 100_000
  @modes ~w(unknown stationary walking running cycling driving bus train flying boat motorcycle)

  @count_sql """
  SELECT count(*) FROM points
  WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 AND lonlat IS NOT NULL
    AND (anomaly IS NULL OR anomaly = FALSE)
    AND NOT ST_DWithin(lonlat::geography, ST_SetSRID(ST_MakePoint(0, 0), 4326)::geography, 5000)
  """

  @points_sql """
  SELECT id, ST_Y(lonlat::geometry) AS lat, ST_X(lonlat::geometry) AS lon, timestamp, accuracy
  FROM points
  WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 AND lonlat IS NOT NULL
    AND (anomaly IS NULL OR anomaly = FALSE)
    AND NOT (ST_X(lonlat::geometry) = 0 AND ST_Y(lonlat::geometry) = 0)
  ORDER BY timestamp ASC
  """

  @segments_sql """
  SELECT s.transportation_mode, s.confidence_score, s.corrected_at IS NOT NULL,
         floor(extract(epoch FROM s.start_at))::bigint, floor(extract(epoch FROM s.end_at))::bigint
  FROM track_segments s JOIN tracks t ON t.id = s.track_id
  WHERE t.user_id = $1 AND s.start_at IS NOT NULL AND s.end_at IS NOT NULL
    AND s.start_at <= to_timestamp($2::bigint) AND s.end_at >= to_timestamp($3::bigint)
  ORDER BY s.start_at
  """

  def load(repo, user_id, start, stop) do
    [[count]] = repo.query!(@count_sql, [user_id, start, stop], log: false).rows

    if count > @max_candidate_points do
      Logger.warning(
        "[Visits::Detection::CandidateLoader skip] user_id=#{user_id} range=#{start}..#{stop} " <>
          "candidate_points=#{count} max=#{@max_candidate_points}"
      )

      %{points: [], segments: [], skipped: true}
    else
      %{
        points: points(repo, user_id, start, stop),
        segments: segments(repo, user_id, start, stop),
        skipped: false
      }
    end
  end

  defp points(repo, user_id, start, stop) do
    {:ok, rows} =
      repo.transaction(fn ->
        repo.query!("SELECT set_config('statement_timeout', '30000', true)", [], log: false)
        repo.query!(@points_sql, [user_id, start, stop], log: false).rows
      end)

    for [id, lat, lon, ts, accuracy] <- rows,
        do: %{id: id, lat: lat, lon: lon, timestamp: ts, accuracy: accuracy}
  end

  defp segments(repo, user_id, start, stop) do
    for [mode, confidence, corrected, start_ts, end_ts] <-
          repo.query!(@segments_sql, [user_id, stop, start], log: false).rows,
        do: %{
          mode: Enum.at(@modes, mode),
          confidence: confidence,
          corrected: corrected,
          start_ts: start_ts,
          end_ts: end_ts
        }
  end
end
