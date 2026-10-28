# frozen_string_literal: true

module Achievements
  class CountryDwellCalculator
    MAX_TIMESTAMP = (2**63) - 1
    PAIR_CAP_SECONDS = 30.minutes.to_i
    COVERAGE_THRESHOLD = 0.9

    CELL_SQL = 'FLOOR(ST_%<axis>s(p.lonlat::geometry) / %%<grid>f)::int'
    SCOPE_SQL = <<~SQL
      p.user_id = %<user_id>d
        AND p."timestamp" >= %<since>d
        AND p."timestamp" <= %<through>d
        AND p.lonlat IS NOT NULL
        AND (p.anomaly IS DISTINCT FROM TRUE)
    SQL

    # Exact per-point checks only for points in cells whose envelope touches
    # a disputed area: one index probe per cell instead of per point.
    POINTS_SQL = <<~SQL.freeze
      WITH cells AS MATERIALIZED (
        SELECT #{format(CELL_SQL, axis: 'X')} AS gx, #{format(CELL_SQL, axis: 'Y')} AS gy,
               BOOL_OR(p.country_id IS NULL) AS untagged
        FROM points p
        WHERE #{SCOPE_SQL}
        GROUP BY 1, 2
      ),
      candidate_cells AS MATERIALIZED (
        SELECT cells.gx, cells.gy
        FROM cells
        WHERE #{DisputedArea.near_cell_sql('cells.gx', 'cells.gy', GridDwellCalculator::GRID_DEGREES)}
      ),
      untagged_cells AS MATERIALIZED (
        SELECT cells.gx, cells.gy, m.code
        FROM cells
        LEFT JOIN LATERAL (
          SELECT c.iso_a2 AS code
          FROM countries c
          WHERE ST_Intersects(
            c.geom,
            ST_SetSRID(ST_MakePoint((cells.gx + 0.5) * %<grid>f, (cells.gy + 0.5) * %<grid>f), 4326)
          )
          ORDER BY c.iso_a2
          LIMIT 1
        ) m ON TRUE
        WHERE cells.untagged
      ),
      located AS MATERIALIZED (
        SELECT p."timestamp" AS ts, p.id, p.country_id,
               CASE WHEN cc.gx IS NOT NULL AND #{DisputedArea.covering_sql('p.lonlat::geometry')}
                    THEN NULL ELSE COALESCE(c.iso_a2, uc.code) END AS code
        FROM points p
        LEFT JOIN countries c ON c.id = p.country_id
        LEFT JOIN untagged_cells uc
          ON p.country_id IS NULL
         AND uc.gx = #{format(CELL_SQL, axis: 'X')} AND uc.gy = #{format(CELL_SQL, axis: 'Y')}
        LEFT JOIN candidate_cells cc
          ON cc.gx = #{format(CELL_SQL, axis: 'X')} AND cc.gy = #{format(CELL_SQL, axis: 'Y')}
        WHERE #{SCOPE_SQL}
      ),
      pts AS MATERIALIZED (
        SELECT ts, country_id, code,
               LEAD(ts) OVER (ORDER BY ts, id) AS next_ts,
               LEAD(code) OVER (ORDER BY ts, id) AS next_code
        FROM located
      )
    SQL

    SQL = POINTS_SQL + <<~SQL
      SELECT NULL::text AS code,
             NULL::bigint AS dwell,
             COUNT(*) FILTER (WHERE country_id IS NOT NULL)::float / NULLIF(COUNT(*), 0) AS coverage
      FROM pts
      UNION ALL
      SELECT code,
             SUM(LEAST(next_ts - ts, %<cap>d))::bigint AS dwell,
             NULL::float AS coverage
      FROM pts
      WHERE code IS NOT NULL AND code = next_code AND next_ts > ts
      GROUP BY code
    SQL

    FIRST_SEEN_SQL = POINTS_SQL + <<~SQL
      SELECT NULL::text AS code,
             NULL::bigint AS timestamp,
             COUNT(*) FILTER (WHERE country_id IS NOT NULL)::float / NULLIF(COUNT(*), 0) AS coverage
      FROM pts
      UNION ALL
      SELECT code, MIN(ts)::bigint AS timestamp, NULL::float AS coverage
      FROM pts
      WHERE code IS NOT NULL
      GROUP BY code
    SQL

    def initialize(user, since: 0, through: MAX_TIMESTAMP)
      @user = user
      @since = since
      @through = through
    end

    def call
      rows = Achievements::PlannedRows.select(sql)
      @country_ids_populated = country_ids_populated?(rows)
      return spatial_fallback unless @country_ids_populated

      rows.reject { |code, _dwell, _coverage| code.nil? }
          .to_h { |code, dwell, _coverage| [code, dwell.to_i] }
    end

    def first_seen(since: @since)
      use_country_ids = @country_ids_populated
      if use_country_ids.nil?
        rows = Achievements::PlannedRows.select(sql(FIRST_SEEN_SQL))
        use_country_ids = country_ids_populated?(rows)
      end
      unless use_country_ids
        return GridDwellCalculator.new(@user, table: 'countries', since: since, through: @through).first_seen
      end

      rows = Achievements::PlannedRows.select(sql(FIRST_SEEN_SQL, since: since)) if rows.nil? || since != @since
      rows.reject { |code, _timestamp, _coverage| code.nil? }
          .to_h { |code, timestamp, _coverage| [code, timestamp.to_i] }
    end

    private

    def sql(template = SQL, since: @since)
      format(template, user_id: @user.id, since: since, through: @through, cap: PAIR_CAP_SECONDS,
                       grid: GridDwellCalculator::GRID_DEGREES)
    end

    def country_ids_populated?(rows)
      coverage = rows.find { |code, _dwell, _coverage| code.nil? }&.last

      coverage.nil? || coverage.to_f >= COVERAGE_THRESHOLD
    end

    def spatial_fallback
      Rails.logger.info(
        "Achievements: country_id coverage below #{COVERAGE_THRESHOLD} for user #{@user.id}, " \
        'falling back to the spatial path'
      )

      GridDwellCalculator.new(@user, table: 'countries', since: @since, through: @through).call
    end
  end
end
