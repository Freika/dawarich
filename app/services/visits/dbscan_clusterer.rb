# frozen_string_literal: true

module Visits
  # Uses PostGIS DBSCAN for efficient spatial clustering of GPS points.
  # This replaces the O(n²) Ruby iteration with database-level clustering.
  class DbscanClusterer
    # Default values (used if user settings not available)
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
      Point.connection.execute("SET LOCAL statement_timeout = '#{QUERY_TIMEOUT_MS}ms'")
      result = Point.connection.execute(dbscan_sql)
      parse_results(result)
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
      user.safe_settings.visit_detection_eps_meters || DEFAULT_EPS_METERS
    end

    def min_points
      user.safe_settings.visit_detection_min_points || DEFAULT_MIN_POINTS
    end

    def time_gap_seconds
      (user.safe_settings.visit_detection_time_gap_minutes || DEFAULT_TIME_GAP_MINUTES) * 60
    end

    def dbscan_sql
      <<-SQL.squish
        WITH clustered_points AS (
          SELECT
            id, lonlat, timestamp, accuracy,
            ST_ClusterDBSCAN(
              ST_Transform(lonlat::geometry, 3857),
              eps := #{eps_meters},
              minpoints := #{min_points}
            ) OVER (ORDER BY timestamp) as spatial_cluster
          FROM points
          WHERE user_id = #{user.id}
            AND timestamp BETWEEN #{start_at} AND #{end_at}
            AND visit_id IS NULL
            AND lonlat IS NOT NULL
          ORDER BY timestamp
        ),
        gap_detection AS (
          SELECT *,
            CASE
              WHEN LAG(timestamp) OVER (PARTITION BY spatial_cluster ORDER BY timestamp) IS NULL THEN 0
              WHEN timestamp - LAG(timestamp) OVER (PARTITION BY spatial_cluster ORDER BY timestamp) > #{time_gap_seconds} THEN 1
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
        HAVING COUNT(*) >= #{min_points}
          AND MAX(timestamp) - MIN(timestamp) >= #{MIN_DURATION_SECONDS}
        ORDER BY MIN(timestamp)
      SQL
    end
  end
end
