# frozen_string_literal: true

module Visits
  # Shared helpers for visit detection: center calculation, radius, place names
  module DetectionHelpers
    DEFAULT_ACCURACY_METERS = 50

    private

    # Calculates the center of points weighted by GPS accuracy.
    # Points with better accuracy (lower value) have higher weight.
    def calculate_weighted_center(points)
      point_array = Array(points)
      return [0.0, 0.0] if point_array.empty?

      total_weight = 0.0
      weighted_lat = 0.0
      weighted_lon = 0.0

      point_array.each do |point|
        accuracy = point.accuracy || default_accuracy_meters
        weight = 1.0 / [accuracy, 1].max

        weighted_lat += point.lat * weight
        weighted_lon += point.lon * weight
        total_weight += weight
      end

      [weighted_lat / total_weight, weighted_lon / total_weight]
    end

    def default_accuracy_meters
      return DEFAULT_ACCURACY_METERS unless respond_to?(:user) && user

      user.safe_settings.visit_detection_default_accuracy
    end

    def calculate_visit_radius(points, center)
      point_array = Array(points)
      return 15 if point_array.empty?

      max_distance = point_array.map do |point|
        Geocoder::Calculations.distance_between(center, [point.lat, point.lon], units: :km)
      end.max

      [(max_distance * 1000), 15].max
    end

    def suggest_place_name(points)
      place_name_suggester.new(points).call
    end

    def fetch_place_name(center)
      Visits::Names::Fetcher.new(center).call
    end

    def place_name_suggester
      Visits::Names::Suggester
    end
  end
end
