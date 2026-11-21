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

    # A cell whose centre misses every shape but whose square still touches one
    # is a coast or border cell: its centre says nothing about the points in it.
    # Each such shape is clipped to the cell once, and the cell's points are
    # matched against those small pieces, so no point is tested against a
    # full-resolution boundary and open-ocean cells cost one index probe.
    def self.edge_pieces_sql(table, code_column, cells)
      envelope = "ST_MakeEnvelope(e.gx * #{GRID_DEGREES}, e.gy * #{GRID_DEGREES}, " \
                 "(e.gx + 1) * #{GRID_DEGREES}, (e.gy + 1) * #{GRID_DEGREES}, 4326)"

      "SELECT e.gx, e.gy, s.#{code_column} AS code, ST_Intersection(s.geom, #{envelope}) AS geom " \
        "FROM #{cells} e JOIN #{table} s ON ST_Intersects(s.geom, #{envelope}) WHERE e.code IS NULL"
    end

    # The lowest code of the edge pieces that contain each point, as the centre
    # lookup's ORDER BY ... LIMIT 1 does.
    def self.edge_codes_sql(scope_sql)
      'SELECT p.id, MIN(ep.code) AS code FROM points p JOIN edge_pieces ep ' \
        "ON ep.gx = FLOOR(ST_X(p.lonlat::geometry) / #{GRID_DEGREES})::int " \
        "AND ep.gy = FLOOR(ST_Y(p.lonlat::geometry) / #{GRID_DEGREES})::int " \
        "AND ST_Intersects(ep.geom, p.lonlat::geometry) WHERE #{scope_sql} GROUP BY p.id"
    end

    SCOPE_SQL = <<~SQL.squish
      p.user_id = %<user_id>d
        AND p."timestamp" >= %<since>d
        AND p."timestamp" <= %<through>d
        AND p.lonlat IS NOT NULL
        AND (p.anomaly IS DISTINCT FROM TRUE)
    SQL

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
      cell_codes AS MATERIALIZED (
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
      edge_pieces AS MATERIALIZED (#{edge_pieces_sql('%<table>s', '%<code_column>s', 'cell_codes')}),
      edge_codes AS MATERIALIZED (#{edge_codes_sql(SCOPE_SQL)}),
      located AS (
        SELECT p."timestamp" AS ts, p.id, p.country_id,
               CASE WHEN cc.near_disputed AND #{DisputedArea.covering_sql('p.lonlat::geometry')}
                    THEN NULL ELSE COALESCE(cc.code, ec.code) END AS code
        FROM points p
        LEFT JOIN cell_codes cc
          ON cc.gx = FLOOR(ST_X(p.lonlat::geometry) / %<grid>f)::int
         AND cc.gy = FLOOR(ST_Y(p.lonlat::geometry) / %<grid>f)::int
        LEFT JOIN edge_codes ec ON ec.id = p.id
        WHERE #{SCOPE_SQL}
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
