# frozen_string_literal: true

module Visits
  class StayPointDetector
    MAX_CANDIDATE_POINTS = 100_000
    DRIFT_CAP_FACTOR = 1.5
    QUERY_TIMEOUT_MS = 30_000

    Pt = Struct.new(:id, :lat, :lon, :timestamp, :accuracy)

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
          "[Visits::StayPointDetector skip] user_id=#{user.id} range=#{start_at}..#{end_at} " \
          "candidate_points=#{candidate_count} max=#{MAX_CANDIDATE_POINTS}"
        )
        return []
      end

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      stays = merge_brief_reentries(sweep(load_points))
      clusters = stays.each_with_index.map { |stay, index| to_cluster(stay, index) }
      log_success(candidate_count, clusters.size, started_at)
      clusters
    end

    private

    def stay_radius_meters = user.safe_settings.visit_radius_meters
    def min_dwell_seconds  = user.safe_settings.visit_min_duration_minutes * 60
    def min_points         = user.safe_settings.visit_min_points
    def max_gap_seconds    = user.safe_settings.stay_max_gap_minutes * 60
    def merge_gap_seconds  = user.safe_settings.merge_threshold_minutes * 60

    def sweep(points)
      stays = []
      open = nil

      points.each do |point|
        if open.nil?
          open = open_stay(point)
          next
        end

        over_gap = (point.timestamp - open[:last].timestamp) > max_gap_seconds
        joins = over_gap ? near_anchor?(open, point) : colocated?(open, point)

        if joins
          add_member(open, point)
          # After bridging a long gap, the pre-gap drift reference is stale; re-anchor the drift
          # check to this post-gap point. `first` is left untouched so start_time spans the gap.
          open[:drift_ref] = point if over_gap
        else
          finished = build_stay(open)
          stays << finished if finished
          open = open_stay(point)
        end
      end

      finished = build_stay(open)
      stays << finished if finished
      stays
    end

    # Within a continuous track: radius test plus a drift cap from the first member,
    # so a slow walker can't drag the running-mean circle into one giant blob.
    def colocated?(open, point)
      d = distance_meters(open[:anchor_lat], open[:anchor_lon], point.lat, point.lon)
      d_ref = distance_meters(open[:drift_ref].lat, open[:drift_ref].lon, point.lat, point.lon)

      d <= stay_radius_meters && d_ref <= stay_radius_meters * DRIFT_CAP_FACTOR
    end

    # After a gap longer than stay_max_gap_minutes (e.g. dead battery): judge only by the
    # running-mean center. The pre-gap first-member reference is stale, so the drift cap is skipped.
    def near_anchor?(open, point)
      distance_meters(open[:anchor_lat], open[:anchor_lon], point.lat, point.lon) <= stay_radius_meters
    end

    def open_stay(point)
      {
        members: [point.id],
        first: point,
        drift_ref: point,
        last: point,
        sum_lat: point.lat,
        sum_lon: point.lon,
        count: 1,
        anchor_lat: point.lat,
        anchor_lon: point.lon
      }
    end

    def add_member(open, point)
      open[:members] << point.id
      open[:last] = point
      open[:sum_lat] += point.lat
      open[:sum_lon] += point.lon
      open[:count] += 1
      open[:anchor_lat] = open[:sum_lat] / open[:count]
      open[:anchor_lon] = open[:sum_lon] / open[:count]
    end

    def build_stay(open)
      return nil if open.nil?

      duration = open[:last].timestamp - open[:first].timestamp
      return nil if duration < min_dwell_seconds
      return nil if open[:members].size < min_points

      {
        point_ids: open[:members],
        start_time: open[:first].timestamp,
        end_time: open[:last].timestamp,
        point_count: open[:members].size,
        center_lat: open[:anchor_lat],
        center_lon: open[:anchor_lon]
      }
    end

    def merge_brief_reentries(stays)
      sorted = stays.sort_by { |stay| stay[:start_time] }
      merged = []

      sorted.each do |stay|
        previous = merged.last
        if previous && mergeable?(previous, stay)
          merge_into(previous, stay)
        else
          merged << stay
        end
      end

      merged
    end

    # Fold stay into previous, updating the centroid (point-count weighted) so a multi-hop
    # A→B→C chain compares C against the true A+B centre, not A's original centre.
    def merge_into(previous, stay)
      a = previous[:point_count]
      b = stay[:point_count]
      total = a + b
      previous[:center_lat] = ((previous[:center_lat] * a) + (stay[:center_lat] * b)) / total
      previous[:center_lon] = ((previous[:center_lon] * a) + (stay[:center_lon] * b)) / total
      previous[:point_ids].concat(stay[:point_ids])
      previous[:end_time] = stay[:end_time]
      previous[:point_count] = previous[:point_ids].size
    end

    def mergeable?(previous, stay)
      gap = stay[:start_time] - previous[:end_time]
      return false if gap > merge_gap_seconds

      distance_meters(previous[:center_lat], previous[:center_lon],
                      stay[:center_lat], stay[:center_lon]) <= stay_radius_meters
    end

    def to_cluster(stay, index)
      {
        visit_id: "sp-#{index}",
        point_ids: stay[:point_ids],
        start_time: stay[:start_time],
        end_time: stay[:end_time],
        point_count: stay[:point_count]
      }
    end

    def distance_meters(lat1, lon1, lat2, lon2)
      Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km) * 1000
    end

    def load_points
      sql = ActiveRecord::Base.sanitize_sql_array(
        [
          <<~SQL.squish,
            SELECT id,
                   ST_Y(lonlat::geometry) AS lat,
                   ST_X(lonlat::geometry) AS lon,
                   timestamp,
                   accuracy
            FROM points
            WHERE user_id = ?
              AND visit_id IS NULL
              AND timestamp BETWEEN ? AND ?
              AND lonlat IS NOT NULL
              AND (anomaly IS NULL OR anomaly = FALSE)
            ORDER BY timestamp ASC
          SQL
          user.id, start_at, end_at
        ]
      )

      conn = ActiveRecord::Base.connection
      # SET LOCAL binds the timeout to this transaction's backend so it survives PgBouncer
      # transaction pooling — a bare SET + query can otherwise land on different servers.
      conn.transaction do
        conn.exec_query("SET LOCAL statement_timeout = #{QUERY_TIMEOUT_MS}", 'StayPointDetector Timeout')
        conn.exec_query(sql, 'StayPointDetector Load').map do |row|
          Pt.new(row['id'].to_i, row['lat'].to_f, row['lon'].to_f, row['timestamp'].to_i, row['accuracy']&.to_i)
        end
      end
    end

    def count_candidate_points
      Point.where(user_id: user.id, visit_id: nil)
           .where(timestamp: start_at..end_at)
           .where('lonlat IS NOT NULL')
           .where('anomaly IS NULL OR anomaly = FALSE')
           .count
    end

    def log_success(candidate_count, cluster_count, started_at)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).to_i
      Rails.logger.info(
        "[Visits::StayPointDetector] user_id=#{user.id} range=#{start_at}..#{end_at} " \
        "candidate_points=#{candidate_count} clusters=#{cluster_count} duration_ms=#{duration_ms}"
      )
    end
  end
end
