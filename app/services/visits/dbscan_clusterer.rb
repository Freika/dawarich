# frozen_string_literal: true

module Visits
  # Uses PostGIS DBSCAN for efficient spatial clustering of GPS points.
  # This replaces the O(n²) Ruby iteration with database-level clustering.
  #
  # Points are transformed to EPSG:4978 (geocentric 3D Cartesian, meters) before
  # clustering, so eps is passed directly in meters. This works correctly at all
  # latitudes including poles and across the dateline.
  class DbscanClusterer
    MIN_DURATION_SECONDS = 180 # 3 minutes (not configurable)
    QUERY_TIMEOUT_MS = 30_000 # 30 seconds timeout for DBSCAN query

    attr_reader :user, :start_at, :end_at

    def initialize(user, start_at:, end_at:)
      @user = user
      @start_at = start_at.to_i
      @end_at = end_at.to_i
    end

    def call
      execute_dbscan_query
    end

    private

    def execute_dbscan_query
      # Wrap in transaction so SET LOCAL applies to the DBSCAN query
      Point.transaction do
        Point.connection.execute(
          ActiveRecord::Base.sanitize_sql_array(
            ['SET LOCAL statement_timeout = ?', "#{QUERY_TIMEOUT_MS}ms"]
          )
        )
        result = Point.connection.execute(dbscan_sql)
        parse_results(result)
      end
    rescue ActiveRecord::StatementInvalid => e
      raise e unless e.message.include?('canceling statement due to statement timeout')

      Rails.logger.warn("DBSCAN query timed out after #{QUERY_TIMEOUT_MS}ms for user #{user.id}")
      nil
    end

    def parse_results(result)
      result.map do |row|
        {
          visit_id: row['visit_id'],
          point_ids: parse_array(row['point_ids']),
          start_time: row['start_time'].to_i,
          end_time: row['end_time'].to_i,
          point_count: row['point_count'].to_i
        }
      end
    end

    def parse_array(array_string)
      return [] if array_string.nil?
      return array_string if array_string.is_a?(Array)

      array_string.gsub(/[{}]/, '').split(',').map(&:to_i)
    end

    def eps_meters
      user.safe_settings.visit_detection_eps_meters
    end

    def min_points
      user.safe_settings.visit_detection_min_points
    end

    def time_gap_seconds
      user.safe_settings.visit_detection_time_gap_minutes * 60
    end

    def density_normalization_enabled?
      user.safe_settings.density_normalization_enabled?
    end

    def density_gap_threshold_seconds
      density_normalization_enabled? ? user.safe_settings.density_gap_threshold_seconds : 0
    end

    def density_max_gap_seconds
      density_normalization_enabled? ? user.safe_settings.density_max_gap_minutes * 60 : 0
    end

    def density_max_distance_meters
      density_normalization_enabled? ? user.safe_settings.density_max_distance_meters : 0
    end

    def dbscan_sql
      params = [user.id, start_at, end_at,
                density_gap_threshold_seconds, density_max_gap_seconds, density_max_distance_meters,
                eps_meters, min_points,
                time_gap_seconds, min_points, MIN_DURATION_SECONDS]
      ActiveRecord::Base.sanitize_sql_array([<<-SQL.squish, *params])
        WITH candidate_points AS (
          SELECT id, lonlat, timestamp, accuracy
          FROM points
          WHERE user_id = ?
            AND timestamp BETWEEN ? AND ?
            AND visit_id IS NULL
            AND lonlat IS NOT NULL
        ),
        point_gaps AS (
          SELECT
            id, lonlat, timestamp, accuracy,
            LEAD(id) OVER w AS next_id,
            LEAD(lonlat) OVER w AS next_lonlat,
            LEAD(timestamp) OVER w AS next_timestamp,
            LEAD(timestamp) OVER w - timestamp AS gap_seconds,
            ST_Distance(lonlat::geography, LEAD(lonlat) OVER w::geography) AS gap_distance_m
          FROM candidate_points
          WINDOW w AS (ORDER BY timestamp)
        ),
        synthetic_points AS (
          SELECT
            -(ROW_NUMBER() OVER ())::bigint AS id,
            ST_LineInterpolatePoint(
              ST_MakeLine(pg.lonlat::geometry, pg.next_lonlat::geometry),
              s.frac
            )::geography AS lonlat,
            pg.timestamp + (s.frac * pg.gap_seconds)::integer AS timestamp,
            GREATEST(pg.accuracy, 100) AS accuracy
          FROM point_gaps pg
          CROSS JOIN LATERAL (
            SELECT generate_series(1, GREATEST(FLOOR(pg.gap_seconds / 15.0)::int - 1, 0))::float
                   / FLOOR(pg.gap_seconds / 15.0) AS frac
          ) s
          WHERE pg.gap_seconds > ?
            AND pg.gap_seconds <= ?
            AND pg.gap_distance_m <= ?
            AND pg.next_id IS NOT NULL
        ),
        all_points AS (
          SELECT id, lonlat, timestamp, accuracy FROM candidate_points
          UNION ALL
          SELECT id, lonlat, timestamp, accuracy FROM synthetic_points
        ),
        clustered_points AS (
          SELECT
            ap.id, ap.lonlat, ap.timestamp, ap.accuracy,
            ST_ClusterDBSCAN(
              ST_Force3D(ST_Transform(ap.lonlat::geometry, 4978)),
              eps := ?::double precision,
              minpoints := ?
            ) OVER () as spatial_cluster
          FROM all_points ap
          ORDER BY ap.timestamp
        ),
        gap_detection AS (
          SELECT *,
            CASE
              WHEN LAG(timestamp) OVER (PARTITION BY spatial_cluster ORDER BY timestamp) IS NULL THEN 0
              WHEN timestamp - LAG(timestamp) OVER (PARTITION BY spatial_cluster ORDER BY timestamp) > ? THEN 1
              ELSE 0
            END as new_segment
          FROM clustered_points
          WHERE spatial_cluster IS NOT NULL
        ),
        visit_groups AS (
          SELECT *,
            CONCAT(spatial_cluster, '-', SUM(new_segment) OVER (PARTITION BY spatial_cluster ORDER BY timestamp)) as visit_id
          FROM gap_detection
        )
        SELECT
          visit_id,
          array_agg(id ORDER BY timestamp) as point_ids,
          MIN(timestamp) as start_time,
          MAX(timestamp) as end_time,
          COUNT(*) as point_count
        FROM visit_groups
        GROUP BY visit_id
        HAVING COUNT(*) >= ?
          AND MAX(timestamp) - MIN(timestamp) >= ?
        ORDER BY MIN(timestamp)
      SQL
    end
  end
end
