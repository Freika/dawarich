defmodule Dawarich.Achievements.Dwell do
  @moduledoc false

  @coverage_threshold 0.9

  @country_sql """
  WITH pts AS MATERIALIZED (
    SELECT p."timestamp" AS ts,
           p.country_id AS country_id,
           c.iso_a2 AS code,
           LEAD(p."timestamp") OVER (ORDER BY p."timestamp", p.id) AS next_ts,
           LEAD(c.iso_a2) OVER (ORDER BY p."timestamp", p.id) AS next_code
    FROM points p
    LEFT JOIN countries c ON c.id = p.country_id
    WHERE p.user_id = $1
      AND p."timestamp" >= $2
      AND p."timestamp" <= $3
      AND p.lonlat IS NOT NULL
      AND (p.anomaly IS DISTINCT FROM TRUE)
  )
  SELECT NULL::text AS code,
         NULL::bigint AS dwell,
         COUNT(*) FILTER (WHERE country_id IS NOT NULL)::float / NULLIF(COUNT(*), 0) AS coverage
  FROM pts
  UNION ALL
  SELECT code,
         SUM(LEAST(next_ts - ts, 1800))::bigint AS dwell,
         NULL::float AS coverage
  FROM pts
  WHERE code IS NOT NULL AND code = next_code AND next_ts > ts
  GROUP BY code
  """

  @grid_template """
  WITH cells AS (
    SELECT DISTINCT FLOOR(ST_X(lonlat::geometry) / 0.010000)::int AS gx,
                    FLOOR(ST_Y(lonlat::geometry) / 0.010000)::int AS gy
    FROM points
    WHERE user_id = $1
      AND "timestamp" >= $2
      AND "timestamp" <= $3
      AND lonlat IS NOT NULL
      AND (anomaly IS DISTINCT FROM TRUE)
  ),
  cell_codes AS (
    SELECT c.gx, c.gy, m.code
    FROM cells c
    LEFT JOIN LATERAL (
      SELECT s.__CODE__ AS code
      FROM __TABLE__ s
      WHERE ST_Intersects(
        s.geom,
        ST_SetSRID(ST_MakePoint((c.gx + 0.5) * 0.010000, (c.gy + 0.5) * 0.010000), 4326)
      )
      ORDER BY s.__CODE__
      LIMIT 1
    ) m ON TRUE
  ),
  pts AS (
    SELECT p."timestamp" AS ts,
           cc.code,
           LEAD(p."timestamp") OVER (ORDER BY p."timestamp", p.id) AS next_ts,
           LEAD(cc.code) OVER (ORDER BY p."timestamp", p.id) AS next_code
    FROM points p
    LEFT JOIN cell_codes cc
      ON cc.gx = FLOOR(ST_X(p.lonlat::geometry) / 0.010000)::int
     AND cc.gy = FLOOR(ST_Y(p.lonlat::geometry) / 0.010000)::int
    WHERE p.user_id = $1
      AND p."timestamp" >= $2
      AND p."timestamp" <= $3
      AND p.lonlat IS NOT NULL
      AND (p.anomaly IS DISTINCT FROM TRUE)
  )
  SELECT code, SUM(LEAST(next_ts - ts, 1800))::bigint
  FROM pts
  WHERE code IS NOT NULL AND code = next_code AND next_ts > ts
  GROUP BY code
  """

  @grid_sql %{
    "regions" =>
      @grid_template
      |> String.replace("__TABLE__", "regions")
      |> String.replace("__CODE__", "code"),
    "countries" =>
      @grid_template
      |> String.replace("__TABLE__", "countries")
      |> String.replace("__CODE__", "iso_a2")
  }

  def deltas(repo, user_id, since, through),
    do:
      Map.merge(
        countries(repo, user_id, since, through),
        grid(repo, "regions", user_id, since, through)
      )

  def countries(repo, user_id, since, through) do
    rows = repo.query!(@country_sql, [user_id, since, through], log: false).rows

    coverage =
      case Enum.find(rows, &match?([nil | _], &1)) do
        [_code, _dwell, value] -> value
        nil -> nil
      end

    if is_nil(coverage) or coverage >= @coverage_threshold,
      do: for([code, dwell, _] <- rows, code != nil, into: %{}, do: {code, dwell}),
      else: grid(repo, "countries", user_id, since, through)
  end

  def grid(repo, source, user_id, since, through) do
    repo.query!(Map.fetch!(@grid_sql, source), [user_id, since, through], log: false).rows
    |> Map.new(fn [code, dwell] -> {code, dwell} end)
  end
end
