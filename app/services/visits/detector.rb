# frozen_string_literal: true

module Visits
  # Detects potential visits from a collection of tracked points
  class Detector
    MINIMUM_VISIT_DURATION = 3.minutes
    MAXIMUM_VISIT_GAP = 30.minutes
    MINIMUM_POINTS_FOR_VISIT = 2

    attr_reader :points, :place_name_suggester

    def initialize(points)
      @points = points
      @place_name_suggester = PlaceNameSuggester
    end

    def detect_potential_visits
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

    private

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
      center = calculate_center(points)

      visit.merge(
        duration: visit[:end_time] - visit[:start_time],
        center_lat: center[0],
        center_lon: center[1],
        radius: calculate_visit_radius(points, center),
        suggested_name: suggest_place_name(points)
      )
    end

    def calculate_center(points)
      lat_sum = points.sum(&:lat)
      lon_sum = points.sum(&:lon)
      count = points.size.to_f

      [lat_sum / count, lon_sum / count]
    end

    def calculate_visit_radius(points, center)
      max_distance = points.map do |point|
        Geocoder::Calculations.distance_between(center, [point.lat, point.lon], units: :km)
      end.max

      # Convert to meters and ensure minimum radius
      [(max_distance * 1000), 15].max
    end

    def suggest_place_name(points)
      place_name_suggester.new(points).call
    end
  end
end
