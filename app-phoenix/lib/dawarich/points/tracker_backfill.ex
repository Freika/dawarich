defmodule Dawarich.Points.TrackerBackfill do
  @moduledoc false

  @batch """
  WITH batch AS (
    SELECT id FROM points WHERE user_id=$1 AND id>$2
    AND (tracker_id IS NULL OR tracker_id IN ('google-maps-timeline-export','google-maps-phone-timeline-export'))
    AND (length(btrim(raw_data->>'deviceTag'))>0 OR length(btrim(raw_data->>'tid'))>0 OR import_id IS NOT NULL)
    ORDER BY id LIMIT 5000
  ), bounds AS (SELECT max(id) AS max_id FROM batch)
  UPDATE points SET tracker_id=(CASE
    WHEN length(btrim(points.raw_data->>'deviceTag'))>0 THEN 'google-records-device-' || btrim(points.raw_data->>'deviceTag')
    WHEN length(btrim(points.raw_data->>'tid'))>0 THEN btrim(points.raw_data->>'tid')
    ELSE 'legacy-import-' || points.import_id::text END), updated_at=NOW()
  FROM batch,bounds WHERE points.id=batch.id RETURNING bounds.max_id
  """

  def run(repo, user_id, opts \\ []), do: run(repo, user_id, 0, 0, opts)

  defp run(repo, user_id, cursor, total, opts) do
    case repo.query!(@batch, [user_id, cursor], log: false) do
      %{num_rows: 0} ->
        total

      %{num_rows: count, rows: [[last] | _]} ->
        if hook = opts[:after_batch], do: hook.(count, last)
        run(repo, user_id, last, total + count, opts)
    end
  end
end
