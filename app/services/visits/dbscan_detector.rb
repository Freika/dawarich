# frozen_string_literal: true

module Visits
  # PostGIS DBSCAN-based visit detection. Returns nil on failure so the caller
  # can fall back to iteration-based detection.
  class DbscanDetector
    include DetectionHelpers

    attr_reader :points, :user, :start_at, :end_at

    def initialize(points, user:, start_at:, end_at:)
      @points = points
      @user = user
      @start_at = start_at
      @end_at = end_at
    end

    # Returns an array of visit hashes, or nil if DBSCAN fails (signaling fallback).
    def call
      raw_clusters = DbscanClusterer.new(user, start_at: start_at, end_at: end_at).call
      return nil if raw_clusters.empty?

      all_point_ids = raw_clusters.flat_map { |c| c[:point_ids] }
      points_by_id = Point.where(id: all_point_ids).index_by(&:id)

      raw_clusters.filter_map do |cluster|
        point_ids = cluster[:point_ids]
        cluster_points = point_ids.filter_map { |id| points_by_id[id] }
                                  .sort_by(&:timestamp)
        next if cluster_points.empty?

        finalize_visit_from_cluster(cluster_points, cluster)
      end
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.warn("DBSCAN clustering failed, falling back to iteration: #{e.message}")
      nil
    end

    private

    def finalize_visit_from_cluster(cluster_points, cluster)
      center = calculate_weighted_center(cluster_points)

      {
        start_time: cluster[:start_time],
        end_time: cluster[:end_time],
        duration: cluster[:end_time] - cluster[:start_time],
        center_lat: center[0],
        center_lon: center[1],
        radius: calculate_visit_radius(cluster_points, center),
        points: cluster_points,
        suggested_name: suggest_place_name(cluster_points) || fetch_place_name(center)
      }
    end
  end
end
