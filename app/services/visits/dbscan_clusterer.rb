# frozen_string_literal: true

module Visits
  # Uses PostGIS DBSCAN for efficient spatial clustering of GPS points.
  # This replaces the O(n²) Ruby iteration with database-level clustering.
  #
  # NOTE: Uses EPSG:3857 (Web Mercator) projection for DBSCAN clustering.
  # This introduces distance distortion at higher latitudes — e.g., at 60°N
  # (Oslo, Helsinki), the effective clustering distance is ~half the configured
  # eps_meters value. For most use cases this is acceptable, but users at extreme
  # latitudes may need to increase their clustering distance setting.
  class DbscanClusterer
    DEFAULT_EPS_METERS = 50
    DEFAULT_MIN_POINTS = 2
    DEFAULT_TIME_GAP_MINUTES = 30
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
      [] # Return empty array on timeout, will fall back to iteration
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

      # Parse PostgreSQL array format: {1,2,3}
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

    def dbscan_sql # rubocop:disable Metrics/MethodLength
      params = [eps_meters, min_points, user.id, start_at, end_at,
                time_gap_seconds, min_points, MIN_DURATION_SECONDS]
      ActiveRecord::Base.sanitize_sql_array([<<-SQL.squish, *params])
        WITH clustered_points AS (
          SELECT
            id, lonlat, timestamp, accuracy,
            ST_ClusterDBSCAN(
              ST_Transform(lonlat::geometry, 3857),
              eps := ?,
              minpoints := ?
            ) OVER (ORDER BY timestamp) as spatial_cluster
          FROM points
          WHERE user_id = ?
            AND timestamp BETWEEN ? AND ?
            AND visit_id IS NULL
            AND lonlat IS NOT NULL
          ORDER BY timestamp
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
