defmodule Dawarich.Insights.HeatmapLinks do
  @moduledoc false
  alias Dawarich.Repo

  def year(year, zone) do
    first = Date.new!(year, 1, 1)
    last = Date.new!(year, 12, 31)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT d::date,
          extract(epoch FROM (d AT TIME ZONE $3))::bigint,
          extract(epoch FROM ((d + interval '1 day') AT TIME ZONE $3))::bigint - 1
        FROM generate_series($1::date::timestamp, $2::date::timestamp, interval '1 day') d
        """,
        [first, last, zone],
        log: false
      )

    Map.new(rows, fn [date, first, last] -> {Date.to_iso8601(date), {first, last}} end)
  end
end
