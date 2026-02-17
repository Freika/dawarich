# frozen_string_literal: true

module Visits
  # Detects potential visits from a collection of tracked points
  class Detector
    MINIMUM_VISIT_DURATION = 3.minutes
    MAXIMUM_VISIT_GAP = 30.minutes
    MINIMUM_POINTS_FOR_VISIT = 2
    DEFAULT_ACCURACY_METERS = 50 # Fallback when user settings not available

    attr_reader :points, :place_name_suggester, :user, :start_at, :end_at, :use_dbscan

    def initialize(points, user: nil, start_at: nil, end_at: nil, use_dbscan: true)
      @points = points
      @user = user
      @start_at = start_at
      @end_at = end_at
      @use_dbscan = use_dbscan
      @place_name_suggester = Visits::Names::Suggester
    end

    def detect_potential_visits
      if use_dbscan && user && start_at && end_at
        detect_with_dbscan
      else
        detect_with_iteration
      end
    end

    private

    # PostGIS DBSCAN-based detection (preferred)
    def detect_with_dbscan
      raw_clusters = DbscanClusterer.new(user, start_at: start_at, end_at: end_at).call
      return detect_with_iteration if raw_clusters.empty?

      # Batch load all points to avoid N+1 queries
      all_point_ids = raw_clusters.flat_map { |c| c[:point_ids] }
      points_by_id = Point.where(id: all_point_ids).index_by(&:id)

      raw_clusters.filter_map do |cluster|
        cluster_points = cluster[:point_ids]
          .filter_map { |id| points_by_id[id] }
          .sort_by(&:timestamp)
        next if cluster_points.empty?

        finalize_visit_from_cluster(cluster_points, cluster)
      end
    rescue ActiveRecord::StatementInvalid, PG::Error => e
      Rails.logger.warn("DBSCAN clustering failed, falling back to iteration: #{e.message}")
      detect_with_iteration
    end

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

    # Ruby iteration-based detection (fallback)
    def detect_with_iteration
      visits = []
      current_visit = nil

      points.each do |point|
        if current_visit.nil?
          current_visit = initialize_visit(point)
          next
        end

        if belongs_to_current_visit?(point, current_visit)
          current_visit[:points] << point
          current_visit[:end_time] = point.timestamp
        else
          visits << finalize_visit(current_visit) if valid_visit?(current_visit)
          current_visit = initialize_visit(point)
        end
      end

      # Handle the last visit
      visits << finalize_visit(current_visit) if current_visit && valid_visit?(current_visit)

      visits
    end

    def initialize_visit(point)
      {
        start_time: point.timestamp,
        end_time: point.timestamp,
        center_lat: point.lat,
        center_lon: point.lon,
        points: [point]
      }
    end

    def belongs_to_current_visit?(point, visit)
      time_gap = point.timestamp - visit[:end_time]
      return false if time_gap > MAXIMUM_VISIT_GAP

      # Calculate distance from visit center
      distance = Geocoder::Calculations.distance_between(
        [visit[:center_lat], visit[:center_lon]],
        [point.lat, point.lon],
        units: :km
      )

      # Dynamically adjust radius based on visit duration
      max_radius = calculate_max_radius(visit[:end_time] - visit[:start_time])

      distance <= max_radius
    end

    def calculate_max_radius(duration_seconds)
      # Start with a small radius for short visits, increase for longer stays
      # but cap it at a reasonable maximum
      base_radius = 0.05 # 50 meters
      duration_hours = duration_seconds / 3600.0
      [base_radius * (1 + Math.log(1 + duration_hours)), 0.5].min # Cap at 500 meters
    end

    def valid_visit?(visit)
      duration = visit[:end_time] - visit[:start_time]
      visit[:points].size >= MINIMUM_POINTS_FOR_VISIT && duration >= MINIMUM_VISIT_DURATION
    end

    def finalize_visit(visit)
      points = visit[:points]
      center = calculate_weighted_center(points)

      visit.merge(
        duration: visit[:end_time] - visit[:start_time],
        center_lat: center[0],
        center_lon: center[1],
        radius: calculate_visit_radius(points, center),
        suggested_name: suggest_place_name(points) || fetch_place_name(center)
      )
    end

    # Calculates the center of points weighted by GPS accuracy.
    # Points with better accuracy (lower value) have higher weight.
    def calculate_weighted_center(points)
      point_array = Array(points)
      return [0.0, 0.0] if point_array.empty?

      total_weight = 0.0
      weighted_lat = 0.0
      weighted_lon = 0.0

      point_array.each do |point|
        accuracy = point.accuracy.presence || default_accuracy_meters
        weight = 1.0 / [accuracy, 1].max # Prevent division by zero

        weighted_lat += point.lat * weight
        weighted_lon += point.lon * weight
        total_weight += weight
      end

      return calculate_simple_center(point_array) if total_weight.zero?

      [weighted_lat / total_weight, weighted_lon / total_weight]
    end

    def default_accuracy_meters
      return DEFAULT_ACCURACY_METERS unless user

      user.safe_settings.visit_detection_default_accuracy
    end

    # Simple centroid calculation (fallback)
    def calculate_simple_center(points)
      point_array = Array(points)
      return [0.0, 0.0] if point_array.empty?

      lat_sum = point_array.sum(&:lat)
      lon_sum = point_array.sum(&:lon)
      count = point_array.size.to_f

      [lat_sum / count, lon_sum / count]
    end

    def calculate_visit_radius(points, center)
      point_array = Array(points)
      max_distance = point_array.map do |point|
        Geocoder::Calculations.distance_between(center, [point.lat, point.lon], units: :km)
      end.max

      # Convert to meters and ensure minimum radius
      [(max_distance * 1000), 15].max
    end

    def suggest_place_name(points)
      place_name_suggester.new(points).call
    end

    def fetch_place_name(center)
      Visits::Names::Fetcher.new(center).call
    end
  end
end
