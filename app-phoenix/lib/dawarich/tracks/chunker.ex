defmodule Dawarich.Tracks.Chunker do
  @moduledoc false

  @sql """
  WITH bounds AS (
    SELECT COALESCE($1::timestamptz, (SELECT to_timestamp(min(timestamp)) FROM points WHERE user_id = $3)) AS g_start,
           COALESCE($2::timestamptz, CASE WHEN $1::timestamptz IS NULL
             THEN (SELECT to_timestamp(max(timestamp)) FROM points WHERE user_id = $3) ELSE now() END) AS g_end
  ), edges AS (
    SELECT gs AS c_start, LEAST(gs + interval '1 day', b.g_end) AS c_end, b.g_start, b.g_end
    FROM bounds b, generate_series(b.g_start, b.g_end, interval '1 day') AS gs
    WHERE gs < b.g_end
  ), chunks AS (
    SELECT floor(extract(epoch FROM c_start))::bigint AS start_ts,
           floor(extract(epoch FROM c_end))::bigint AS end_ts,
           floor(extract(epoch FROM GREATEST(c_start - interval '6 hours', g_start)))::bigint AS buffer_start_ts,
           floor(extract(epoch FROM LEAST(c_end + interval '6 hours', g_end)))::bigint AS buffer_end_ts
    FROM edges
  )
  SELECT (row_number() OVER (ORDER BY start_ts) - 1)::int, start_ts, end_ts, buffer_start_ts, buffer_end_ts
  FROM chunks c
  WHERE EXISTS (SELECT 1 FROM points p WHERE p.user_id = $3 AND p.timestamp BETWEEN c.buffer_start_ts AND c.buffer_end_ts)
  ORDER BY start_ts
  """

  def chunks(repo, user_id, start_at, end_at, zone) do
    {:ok, rows} =
      repo.transaction(fn ->
        repo.query!("SELECT set_config('TimeZone', $1, true)", [zone], log: false)
        repo.query!(@sql, [start_at, end_at, user_id], log: false).rows
      end)

    Enum.map(rows, fn [chunk_id, start_ts, end_ts, buffer_start_ts, buffer_end_ts] ->
      %{
        chunk_id: chunk_id,
        start_ts: start_ts,
        end_ts: end_ts,
        buffer_start_ts: buffer_start_ts,
        buffer_end_ts: buffer_end_ts
      }
    end)
  end
end
