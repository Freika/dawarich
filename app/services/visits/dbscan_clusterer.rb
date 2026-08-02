# frozen_string_literal: true

module Visits
  class DbscanClusterer
    QUERY_TIMEOUT_MS = 30_000
    MAX_SYNTHETIC_PER_GAP = 200
    MAX_CANDIDATE_POINTS = 100_000
    DENSITY_GAP_THRESHOLD_SECONDS = 60
    DENSITY_MAX_GAP_SECONDS = 12 * 3600
    DENSITY_MAX_DISTANCE_METERS = 50
    STATIONARY_SPEED_MPS = 1.4
    MAX_CLUSTER_RADIUS_MULTIPLIER = 3

    attr_reader :user, :start_at, :end_at

    def initialize(user, start_at:, end_at:)
      @user = user
      @start_at = start_at.to_i
      @end_at = end_at.to_i
    end

    def call
      candidate_count = count_candidate_points
      if candidate_count > MAX_CANDIDATE_POINTS
        Rails.logger.warn(
          "[Visits::DbscanClusterer skip] user_id=#{user.id} range=#{start_at}..#{end_at} " \
          "candidate_points=#{candidate_count} max=#{MAX_CANDIDATE_POINTS}"
        )
        return []
      end

      conn = ActiveRecord::Base.connection
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      conn.execute("SET statement_timeout = #{QUERY_TIMEOUT_MS}")
      begin
        result = conn.exec_query(dbscan_sql, 'DBSCAN')
        clusters = parse_results(result)
        log_success(clusters, candidate_count, started_at)
        clusters
      ensure
        conn.execute('RESET statement_timeout')
      end
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error("[Visits::DbscanClusterer] user_id=#{user.id} class=#{e.class} message=#{e.message}")
      raise
    end

    private

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

    def parse_array(value)
      return [] if value.nil?
      return value if value.is_a?(Array)

      value.gsub(/[{}]/, '').split(',').map(&:to_i)
    end

    def log_success(clusters, candidate_count, started_at)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).to_i
      Rails.logger.info(
        "[Visits::DbscanClusterer] user_id=#{user.id} range=#{start_at}..#{end_at} " \
        "candidate_points=#{candidate_count} clusters=#{clusters.size} duration_ms=#{duration_ms}"
      )
    end

    def count_candidate_points
      Point.where(user_id: user.id, visit_id: nil)
           .where(timestamp: start_at..end_at)
           .where('lonlat IS NOT NULL')
           .where('anomaly IS NULL OR anomaly = FALSE')
           .count
    end

    def eps_meters
      user.safe_settings.visit_radius_meters
    end

    def min_points
      user.safe_settings.visit_min_points
    end

    def min_duration_seconds
      user.safe_settings.visit_min_duration_minutes * 60
    end

    def time_gap_seconds
      user.safe_settings.time_threshold_minutes * 60
    end

    def density_enabled?
      user.safe_settings.visit_density_fill_enabled?
    end

    def density_threshold_seconds
      density_enabled? ? DENSITY_GAP_THRESHOLD_SECONDS : 0
    end

    def density_max_gap_seconds
      density_enabled? ? DENSITY_MAX_GAP_SECONDS : 0
    end

    def density_max_distance_meters
      density_enabled? ? DENSITY_MAX_DISTANCE_METERS : 0
    end

    def max_cluster_radius_meters
      eps_meters * MAX_CLUSTER_RADIUS_MULTIPLIER
    end

    def dbscan_sql
      params = [
        user.id, start_at, end_at,
        MAX_SYNTHETIC_PER_GAP,
        density_threshold_seconds, density_max_gap_seconds, density_max_distance_meters,
        eps_meters, min_points,
        time_gap_seconds,
        min_points, min_duration_seconds, STATIONARY_SPEED_MPS, max_cluster_radius_meters
      ]
      ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, *params])
        WITH candidate_points AS (
          SELECT id, lonlat, timestamp, accuracy
          FROM points
          WHERE user_id = ?
            AND timestamp BETWEEN ? AND ?
            AND visit_id IS NULL
            AND lonlat IS NOT NULL
            AND (anomaly IS NULL OR anomaly = FALSE)
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
            SELECT generate_series(
                     1,
                     LEAST(GREATEST(FLOOR(pg.gap_seconds / 15.0)::int - 1, 0), ?)
                   )::float
                   / NULLIF(FLOOR(pg.gap_seconds / 15.0), 0) AS frac
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
            ) OVER () AS spatial_cluster
          FROM all_points ap
        ),
        gap_detection AS (
          SELECT *,
            CASE
              WHEN LAG(timestamp) OVER (PARTITION BY spatial_cluster ORDER BY timestamp) IS NULL THEN 0
              WHEN timestamp - LAG(timestamp) OVER (PARTITION BY spatial_cluster ORDER BY timestamp) > ? THEN 1
              ELSE 0
            END AS new_segment
          FROM clustered_points
          WHERE spatial_cluster IS NOT NULL
        ),
        visit_groups AS (
          SELECT *,
            CONCAT(spatial_cluster, '-', SUM(new_segment) OVER (PARTITION BY spatial_cluster ORDER BY timestamp)) AS visit_id
          FROM gap_detection
        ),
        real_point_motion AS (
          SELECT
            visit_id,
            id,
            lonlat,
            timestamp,
            LAG(lonlat) OVER (PARTITION BY visit_id ORDER BY timestamp) AS prev_lonlat,
            LAG(timestamp) OVER (PARTITION BY visit_id ORDER BY timestamp) AS prev_timestamp
          FROM visit_groups
          WHERE id > 0
        ),
        visit_motion AS (
          SELECT
            visit_id,
            COUNT(*) AS real_point_count,
            SUM(
              CASE
                WHEN prev_lonlat IS NULL OR (timestamp - prev_timestamp) <= 0 THEN 0
                ELSE ST_Distance(lonlat::geography, prev_lonlat::geography)
              END
            )::double precision
            / NULLIF(
                SUM(
                  CASE
                    WHEN prev_lonlat IS NULL OR (timestamp - prev_timestamp) <= 0 THEN 0
                    ELSE (timestamp - prev_timestamp)
                  END
                ),
                0
              ) AS avg_speed_mps
          FROM real_point_motion
          GROUP BY visit_id
        ),
        visit_centers AS (
          SELECT
            visit_id,
            ST_Centroid(ST_Collect(lonlat::geometry))::geography AS center
          FROM visit_groups
          WHERE id > 0
          GROUP BY visit_id
        ),
        visit_spreads AS (
          SELECT
            vg.visit_id,
            MAX(ST_Distance(vg.lonlat, vc.center)) AS max_radius_m
          FROM visit_groups vg
          JOIN visit_centers vc USING (visit_id)
          WHERE vg.id > 0
          GROUP BY vg.visit_id
        )
        SELECT
          vg.visit_id,
          array_agg(vg.id ORDER BY vg.timestamp) FILTER (WHERE vg.id > 0) AS point_ids,
          MIN(vg.timestamp) FILTER (WHERE vg.id > 0) AS start_time,
          MAX(vg.timestamp) FILTER (WHERE vg.id > 0) AS end_time,
          COUNT(*) FILTER (WHERE vg.id > 0) AS point_count
        FROM visit_groups vg
        JOIN visit_motion vm USING (visit_id)
        JOIN visit_spreads vs USING (visit_id)
        GROUP BY vg.visit_id, vm.real_point_count, vm.avg_speed_mps, vs.max_radius_m
        HAVING vm.real_point_count >= ?
          AND COALESCE(
                MAX(vg.timestamp) FILTER (WHERE vg.id > 0)
                - MIN(vg.timestamp) FILTER (WHERE vg.id > 0),
                0
              ) >= ?
          AND (vm.avg_speed_mps IS NULL OR vm.avg_speed_mps <= ?::double precision)
          AND vs.max_radius_m <= ?::double precision
        ORDER BY MIN(vg.timestamp) FILTER (WHERE vg.id > 0)
      SQL
    end
  end
end
