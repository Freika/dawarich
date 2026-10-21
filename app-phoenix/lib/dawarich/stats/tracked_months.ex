defmodule Dawarich.Stats.TrackedMonths do
  @moduledoc false

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  @sql """
  WITH RECURSIVE tracked_months AS (
    SELECT MAX(timestamp) AS timestamp FROM points WHERE user_id = $1
    UNION ALL
    SELECT (
      SELECT MAX(points.timestamp) FROM points
      WHERE points.user_id = $1
        AND points.timestamp < EXTRACT(
          EPOCH FROM DATE_TRUNC('month', TO_TIMESTAMP(tracked_months.timestamp))
        )::bigint
    )
    FROM tracked_months WHERE tracked_months.timestamp IS NOT NULL
  )
  SELECT EXTRACT(YEAR FROM TO_TIMESTAMP(timestamp))::integer AS year,
    EXTRACT(MONTH FROM TO_TIMESTAMP(timestamp))::integer AS month_number
  FROM tracked_months WHERE timestamp IS NOT NULL
  ORDER BY year DESC, month_number ASC
  """

  def call(repo, user_id) do
    repo.query!(@sql, [user_id], log: false).rows
    |> Enum.chunk_by(fn [year, _] -> year end)
    |> Enum.map(fn rows ->
      [year, _] = hd(rows)
      %{year: year, months: Enum.map(rows, fn [_, month] -> Enum.at(@months, month - 1) end)}
    end)
  end
end
