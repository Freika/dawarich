# frozen_string_literal: true

class PointsReduce
  DISTANCE_THRESHOLD = 50 # meters
  TIME_THRESHOLD = 10 # seconds

  def initialize(points, distance_threshold: DISTANCE_THRESHOLD, time_threshold: TIME_THRESHOLD)
    @points = points
    @distance_threshold = distance_threshold
    @time_threshold = time_threshold
  end

  def call
    simplify_route
  end

  private

  def simplify_route
    # Array to store the simplified points
    reduced_points = [@points.first]
    previous_point = @points.first
    previous_time = previous_point.timestamp

    @points.each_with_index do |current_point, index|
      next if index.zero? # Skip the first point

      current_time = current_point.timestamp
      time_diff = current_time - previous_time
      distance = distance_between_points(
        previous_point.latitude,
        previous_point.longitude,
        current_point.latitude,
        current_point.longitude
      )

      # Add the point if it's far enough in distance or time
      next unless distance >= @distance_threshold || time_diff >= @time_threshold

      reduced_points << current_point
      previous_point = current_point
      previous_time = current_time
    end

    [@points - reduced_points].flatten.each(&:destroy)
  end

  def distance_between_points(lat1, lon1, lat2, lon2)
    Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km) * 1000 # distance in meters
  end
end
