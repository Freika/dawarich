# frozen_string_literal: true

module Gapfill
  class PointGenerator
    # coordinates: Array of [lon, lat] pairs from BRouter
    # start_point, end_point: existing Point records (endpoints of the gap)
    # user: the User who owns the points
    def initialize(coordinates:, start_point:, end_point:, user:)
      @coordinates = coordinates
      @start_point = start_point
      @end_point = end_point
      @user = user
    end

    # Returns Array of unsaved Point records with interpolated timestamps.
    # Skips the first and last coordinates (those match the existing measured endpoints).
    def build_points
      return [] if @coordinates.size <= 2

      cumulative = cumulative_distances(@coordinates)
      total_distance = cumulative.last
      return [] if total_distance.zero?

      time_span = @end_point.timestamp - @start_point.timestamp

      @coordinates[1..-2].each_with_index.map do |(lon, lat), i|
        fraction = cumulative[i + 1] / total_distance
        timestamp = @start_point.timestamp + (time_span * fraction).to_i

        @user.points.new(
          lonlat: "POINT(#{lon} #{lat})",
          timestamp: timestamp,
          source: :inferred,
          tracker_id: @start_point.tracker_id
        )
      end
    end

    private

    def cumulative_distances(coords)
      distances = [0.0]
      coords.each_cons(2) do |from, to|
        segment = Geocoder::Calculations.distance_between([from[1], from[0]], [to[1], to[0]], units: :km)
        distances << distances.last + segment
      end
      distances
    end
  end
end
