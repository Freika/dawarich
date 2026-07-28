# frozen_string_literal: true

module Visits
  class SmartDetect
    include Visits::AdvisoryLockable

    BATCH_THRESHOLD_DAYS = 31
    BATCH_OVERLAP_SECONDS = 1.hour.to_i

    attr_reader :user, :start_at, :end_at

    def initialize(user, start_at:, end_at:)
      @user = user
      @start_at = clamp_to_plan_window(start_at.to_i)
      @end_at = end_at.to_i
    end

    def call
      return [] if @start_at >= @end_at
      return [] unless points_exist?

      with_user_lock { run }
    end

    private

    def clamp_to_plan_window(timestamp)
      return timestamp unless user.respond_to?(:plan_restricted?) && user.plan_restricted?

      [timestamp, user.data_window_start.to_i].max
    end

    def points_exist?
      Point.where(user_id: user.id, visit_id: nil)
           .not_anomaly
           .where(timestamp: @start_at..@end_at)
           .exists?
    end

    def with_user_lock
      if advisory_locks_enabled?
        ActiveRecord::Base.transaction do
          ActiveRecord::Base.connection.execute(
            ActiveRecord::Base.sanitize_sql_array(['SELECT pg_advisory_xact_lock(?)', user.id.to_i])
          )
          yield
        end
      else
        yield
      end
    end

    def run
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      total_points_in = 0
      total_clusters = 0
      created = []
      ranges = batch_ranges

      ranges.each do |batch_start, batch_end|
        clusters = detect_clusters(batch_start, batch_end)
        next if clusters.empty?

        total_points_in += clusters.sum { |c| c[:point_count] }
        total_clusters  += clusters.size

        potential_visits = build_visit_hashes(clusters)
        merged_visits    = Visits::Merger.new(scoped_batch_points(batch_start,
                                                                  batch_end)).merge_visits(potential_visits)
        grouped_visits   = group_nearby_visits(merged_visits).flatten

        created.concat(
          Visits::Creator.new(user, scoring_on: true).create_visits(grouped_visits)
        )
      end

      log_summary(ranges.size, total_points_in, total_clusters, created.size, started_at)
      created
    end

    def detect_clusters(batch_start, batch_end)
      Visits::StayPointDetector.new(user, start_at: batch_start, end_at: batch_end).call
    rescue StandardError => e
      Rails.logger.warn(
        "[Visits::SmartDetect] StayPointDetector failed, falling back to DbscanClusterer: #{e.class}: #{e.message}"
      )
      ExceptionReporter.call(e, '[Visits::SmartDetect] StayPointDetector failed, falling back to DbscanClusterer')
      Visits::DbscanClusterer.new(user, start_at: batch_start, end_at: batch_end).call
    end

    def batch_ranges
      return [[@start_at, @end_at]] unless should_batch?

      monthly_ranges
    end

    def should_batch?
      ((@end_at - @start_at) / 1.day.to_i) > BATCH_THRESHOLD_DAYS
    end

    def monthly_ranges
      result = []
      cursor = Time.zone.at(@start_at).beginning_of_month
      while cursor.to_i < @end_at
        batch_start = [cursor.to_i, @start_at].max
        batch_end_raw = (cursor.end_of_month + 1.day).beginning_of_day.to_i - 1
        batch_end = [batch_end_raw + BATCH_OVERLAP_SECONDS, @end_at].min
        result << [batch_start, batch_end]
        cursor = cursor.next_month
      end
      result
    end

    def scoped_batch_points(batch_start, batch_end)
      user.scoped_points.not_visited.not_anomaly
          .where(timestamp: batch_start..batch_end)
          .order(timestamp: :asc)
    end

    def build_visit_hashes(clusters)
      all_point_ids = clusters.flat_map { |c| c[:point_ids] }.select(&:positive?)
      points_by_id = Point.where(id: all_point_ids)
                          .select(:id, :visit_id, :lonlat, :timestamp, :accuracy, :geodata)
                          .index_by(&:id)

      clusters.filter_map do |cluster|
        cluster_points = cluster[:point_ids].filter_map { |id| points_by_id[id] }.sort_by(&:timestamp)
        next if cluster_points.empty?

        ClusterHelper.new(cluster_points, cluster).to_visit_hash
      end
    end

    def group_nearby_visits(visits)
      visits.group_by do |visit|
        [
          (visit[:center_lat] * 1000).round / 1000.0,
          (visit[:center_lon] * 1000).round / 1000.0
        ]
      end.values
    end

    def log_summary(batch_count, points_in, clusters, visits_created, started_at)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).to_i
      Rails.logger.info(
        "[Visits::SmartDetect] user_id=#{user.id} range=#{@start_at}..#{@end_at} " \
        'detector=stay_point ' \
        "batches=#{batch_count} points_in=#{points_in} clusters=#{clusters} " \
        "visits_created=#{visits_created} duration_ms=#{duration_ms}"
      )
    end
  end

  class ClusterHelper
    include Visits::DetectionHelpers

    def initialize(points, cluster)
      @points = points
      @cluster = cluster
    end

    def to_visit_hash
      center = calculate_weighted_center(@points)
      {
        start_time: @cluster[:start_time],
        end_time: @cluster[:end_time],
        duration: @cluster[:end_time] - @cluster[:start_time],
        center_lat: center[0],
        center_lon: center[1],
        radius: calculate_visit_radius(@points, center),
        points: @points,
        suggested_name: suggest_place_name(@points) || fetch_place_name(center)
      }
    end
  end
end
