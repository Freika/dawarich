# frozen_string_literal: true

module Achievements
  class GridDwellCalculator
    PAIR_CAP_SECONDS = 30.minutes.to_i
    GRID_DEGREES = 0.01
    SOURCES = {
      'regions' => 'code',
      'countries' => 'iso_a2'
    }.freeze

    SQL = <<~SQL
      WITH cells AS (
        SELECT DISTINCT FLOOR(ST_X(lonlat::geometry) / %<grid>f)::int AS gx,
                        FLOOR(ST_Y(lonlat::geometry) / %<grid>f)::int AS gy
        FROM points
        WHERE user_id = %<user_id>d
          AND "timestamp" >= %<since>d
          AND lonlat IS NOT NULL
          AND (anomaly IS DISTINCT FROM TRUE)
      ),
      cell_codes AS (
        SELECT c.gx, c.gy, m.code
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
      pts AS (
        SELECT p."timestamp" AS ts,
               cc.code,
               LEAD(p."timestamp") OVER (ORDER BY p."timestamp", p.id) AS next_ts,
               LEAD(cc.code) OVER (ORDER BY p."timestamp", p.id) AS next_code
        FROM points p
        LEFT JOIN cell_codes cc
          ON cc.gx = FLOOR(ST_X(p.lonlat::geometry) / %<grid>f)::int
         AND cc.gy = FLOOR(ST_Y(p.lonlat::geometry) / %<grid>f)::int
        WHERE p.user_id = %<user_id>d
          AND p."timestamp" >= %<since>d
          AND p.lonlat IS NOT NULL
          AND (p.anomaly IS DISTINCT FROM TRUE)
      )
      SELECT code, SUM(LEAST(next_ts - ts, %<cap>d))::bigint
      FROM pts
      WHERE code IS NOT NULL AND code = next_code AND next_ts > ts
      GROUP BY code
    SQL

    def initialize(user, table:, since: 0)
      raise ArgumentError, "unsupported source: #{table}" unless SOURCES.key?(table)

      @user = user
      @table = table
      @since = since
    end

    def call
      ApplicationRecord.connection.select_rows(sql).to_h { |code, dwell| [code, dwell.to_i] }
    end

    private

    def sql
      format(SQL, user_id: @user.id, since: @since, cap: PAIR_CAP_SECONDS, grid: GRID_DEGREES,
                  table: @table, code_column: SOURCES.fetch(@table))
    end
  end
end
