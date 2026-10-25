# frozen_string_literal: true

module Achievements
  class GridDwellCalculator
    MAX_TIMESTAMP = (2**63) - 1
    PAIR_CAP_SECONDS = 30.minutes.to_i
    GRID_DEGREES = 0.01
    SOURCES = {
      'regions' => 'code',
      'countries' => 'iso_a2'
    }.freeze

    POINTS_SQL = <<~SQL.freeze
      WITH cells AS (
        SELECT DISTINCT FLOOR(ST_X(lonlat::geometry) / %<grid>f)::int AS gx,
                        FLOOR(ST_Y(lonlat::geometry) / %<grid>f)::int AS gy
        FROM points
        WHERE user_id = %<user_id>d
          AND "timestamp" >= %<since>d
          AND "timestamp" <= %<through>d
          AND lonlat IS NOT NULL
          AND (anomaly IS DISTINCT FROM TRUE)
      ),
      cell_codes AS (
        SELECT c.gx, c.gy, m.code, #{DisputedArea.near_cell_sql('c.gx', 'c.gy', GRID_DEGREES)} AS near_disputed
        FROM cells c
        LEFT JOIN LATERAL (
          SELECT s.%<code_column>s AS code
          FROM %<table>s s
          WHERE ST_Intersects(
            s.geom,
            ST_SetSRID(ST_MakePoint((c.gx + 0.5) * %<grid>f, (c.gy + 0.5) * %<grid>f), 4326)
          )
          ORDER BY s.%<code_column>s
          LIMIT 1
        ) m ON TRUE
      ),
      located AS (
        SELECT p."timestamp" AS ts, p.id, p.country_id,
               CASE WHEN cc.near_disputed AND #{DisputedArea.covering_sql('p.lonlat::geometry')}
                    THEN NULL ELSE cc.code END AS code
        FROM points p
        LEFT JOIN cell_codes cc
          ON cc.gx = FLOOR(ST_X(p.lonlat::geometry) / %<grid>f)::int
         AND cc.gy = FLOOR(ST_Y(p.lonlat::geometry) / %<grid>f)::int
        WHERE p.user_id = %<user_id>d
          AND p."timestamp" >= %<since>d
          AND p."timestamp" <= %<through>d
          AND p.lonlat IS NOT NULL
          AND (p.anomaly IS DISTINCT FROM TRUE)
      ),
      pts AS (
        SELECT ts, country_id, code,
               LEAD(ts) OVER (ORDER BY ts, id) AS next_ts,
               LEAD(code) OVER (ORDER BY ts, id) AS next_code
        FROM located
      )
    SQL

    SQL = POINTS_SQL + <<~SQL
      SELECT code, SUM(LEAST(next_ts - ts, %<cap>d))::bigint
      FROM pts
      WHERE code IS NOT NULL AND code = next_code AND next_ts > ts
      GROUP BY code
    SQL

    FIRST_SEEN_SQL = POINTS_SQL + <<~SQL
      SELECT code, MIN(ts)::bigint
      FROM pts
      WHERE code IS NOT NULL
      GROUP BY code
    SQL

    def initialize(user, table:, since: 0, through: MAX_TIMESTAMP)
      raise ArgumentError, "unsupported source: #{table}" unless SOURCES.key?(table)

      @user = user
      @table = table
      @since = since
      @through = through
    end

    def call
      Achievements::PlannedRows.select(sql).to_h { |code, dwell| [code, dwell.to_i] }
    end

    def first_seen
      Achievements::PlannedRows.select(sql(FIRST_SEEN_SQL)).to_h { |code, timestamp| [code, timestamp.to_i] }
    end

    private

    def sql(template = SQL)
      format(template, user_id: @user.id, since: @since, through: @through, cap: PAIR_CAP_SECONDS, grid: GRID_DEGREES,
                       table: @table, code_column: SOURCES.fetch(@table))
    end
  end
end
