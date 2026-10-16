defmodule Dawarich.Achievements.Dwell do
  @moduledoc false
  alias Dawarich.Achievements.DisputedArea

  @scope ~s(p.user_id = $1 AND p."timestamp" >= $2 AND p."timestamp" <= $3 AND p.lonlat IS NOT NULL AND p.anomaly IS DISTINCT FROM TRUE)
  @gx "FLOOR(ST_X(p.lonlat::geometry) / 0.010000)::int"
  @gy "FLOOR(ST_Y(p.lonlat::geometry) / 0.010000)::int"
  @country """
  WITH candidate_cells AS MATERIALIZED (
    SELECT cells.gx, cells.gy FROM (
      SELECT DISTINCT #{@gx} AS gx, #{@gy} AS gy FROM points p WHERE #{@scope}
    ) cells WHERE #{DisputedArea.near_cell_sql("cells.gx", "cells.gy")}
  ), located AS MATERIALIZED (
    SELECT p."timestamp" AS ts, p.id, p.country_id,
      CASE WHEN cc.gx IS NOT NULL AND #{DisputedArea.covering_sql("p.lonlat::geometry")}
        THEN NULL ELSE c.iso_a2 END AS code
    FROM points p LEFT JOIN countries c ON c.id=p.country_id
    LEFT JOIN candidate_cells cc ON cc.gx=#{@gx} AND cc.gy=#{@gy}
    WHERE #{@scope}
  )
  """
  @pairs """
  , pts AS (
    SELECT ts, country_id, code,
      LEAD(ts) OVER (ORDER BY ts,id) AS next_ts,
      LEAD(code) OVER (ORDER BY ts,id) AS next_code FROM located
  )
  """
  @dwell """
  SELECT code, SUM(LEAST(next_ts-ts,1800))::bigint FROM pts
  WHERE code IS NOT NULL AND code=next_code AND next_ts>ts GROUP BY code
  """
  @first "SELECT code, MIN(ts)::bigint FROM located WHERE code IS NOT NULL"

  def deltas(repo, user, since, through),
    do:
      Map.merge(
        countries(repo, user, since, through),
        grid(repo, "regions", user, since, through)
      )

  def countries(repo, user, since, through) do
    if tagged?(repo, user, since, through),
      do: query(repo, @country <> @pairs <> @dwell, [user, since, through]),
      else: grid(repo, "countries", user, since, through)
  end

  def grid(repo, source, user, since, through),
    do: query(repo, grid_sql(source) <> @pairs <> @dwell, [user, since, through])

  def first_seen(repo, user, since, through) do
    country =
      if tagged?(repo, user, since, through) do
        tagged = query(repo, @country <> @first <> " GROUP BY code", [user, 0, through])

        untagged =
          query(
            repo,
            grid_sql("countries") <> @first <> " AND country_id IS NULL GROUP BY code",
            [user, 0, through]
          )

        Map.merge(tagged, untagged, fn _, a, b -> min(a, b) end)
      else
        query(repo, grid_sql("countries") <> @first <> " GROUP BY code", [user, 0, through])
      end

    Map.merge(
      country,
      query(repo, grid_sql("regions") <> @first <> " GROUP BY code", [user, 0, through])
    )
  end

  defp tagged?(repo, user, since, through) do
    [[coverage]] =
      repo.query!(
        "SELECT COUNT(*) FILTER (WHERE p.country_id IS NOT NULL)::float / NULLIF(COUNT(*),0) FROM points p WHERE " <>
          @scope,
        [user, since, through],
        log: false,
        timeout: :infinity
      ).rows

    is_nil(coverage) or coverage >= 0.9
  end

  defp grid_sql(source) when source in ["countries", "regions"] do
    code = if source == "countries", do: "iso_a2", else: "code"

    """
    WITH cells AS (
      SELECT DISTINCT #{@gx} AS gx, #{@gy} AS gy FROM points p WHERE #{@scope}
    ), cell_codes AS (
      SELECT c.gx,c.gy,m.code,#{DisputedArea.near_cell_sql("c.gx", "c.gy")} AS near_disputed
      FROM cells c LEFT JOIN LATERAL (
        SELECT s.#{code} AS code FROM #{source} s
        WHERE ST_Intersects(s.geom,ST_SetSRID(ST_MakePoint((c.gx+0.5)*0.010000,(c.gy+0.5)*0.010000),4326))
        ORDER BY s.#{code} LIMIT 1
      ) m ON TRUE
    ), located AS (
      SELECT p."timestamp" AS ts,p.id,p.country_id,
        CASE WHEN cc.near_disputed AND #{DisputedArea.covering_sql("p.lonlat::geometry")} THEN NULL ELSE cc.code END AS code
      FROM points p LEFT JOIN cell_codes cc ON cc.gx=#{@gx} AND cc.gy=#{@gy}
      WHERE #{@scope}
    )
    """
  end

  defp query(repo, sql, params),
    do:
      repo.query!(sql, params, log: false, timeout: :infinity).rows
      |> Map.new(fn [code, value] -> {code, value} end)
end
