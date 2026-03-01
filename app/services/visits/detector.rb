# frozen_string_literal: true

module Visits
  # Detects potential visits from a collection of tracked points.
  # Delegates to DBSCAN (preferred) or falls back to iteration-based detection.
  class Detector
    include DetectionHelpers

    MINIMUM_VISIT_DURATION = 3.minutes
    MAXIMUM_VISIT_GAP = 30.minutes
    MINIMUM_POINTS_FOR_VISIT = 2

    attr_reader :points, :user, :start_at, :end_at, :use_dbscan

    def initialize(points, user: nil, start_at: nil, end_at: nil, use_dbscan: true)
      @points = points
      @user = user
      @start_at = start_at
      @end_at = end_at
      @use_dbscan = use_dbscan
    end

    def detect_potential_visits
      if use_dbscan && user && start_at && end_at
        DbscanDetector.new(points, user: user, start_at: start_at, end_at: end_at).call ||
          detect_with_iteration
      else
        detect_with_iteration
      end
    end

    private

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

      distance = Geocoder::Calculations.distance_between(
        [visit[:center_lat], visit[:center_lon]],
        [point.lat, point.lon],
        units: :km
      )

      max_radius = calculate_max_radius(visit[:end_time] - visit[:start_time])

      distance <= max_radius
    end

    def calculate_max_radius(duration_seconds)
      base_radius = 0.05 # 50 meters
      duration_hours = duration_seconds / 3600.0
      [base_radius * (1 + Math.log(1 + duration_hours)), 0.5].min
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
  end
end
