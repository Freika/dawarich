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

      cumulative = cumulative_haversine_distances(@coordinates)
      total_distance = cumulative.last
      return [] if total_distance.zero?

      time_span = @end_point.timestamp - @start_point.timestamp

      @coordinates[1..-2].each_with_index.map do |(lon, lat), i|
        fraction = cumulative[i + 1] / total_distance
        timestamp = @start_point.timestamp + (time_span * fraction).to_i

        @user.points.new(
          lonlat: "POINT(#{lon} #{lat})",
          timestamp: timestamp,
          source: :inferred
        )
      end
    end

    private

    def cumulative_haversine_distances(coords)
      distances = [0.0]
      coords.each_cons(2) do |a, b|
        distances << distances.last + haversine(a, b)
      end
      distances
    end

    def haversine(a, b) # rubocop:disable Naming/MethodParameterName
      r = 6_371_000.0
      lat1 = a[1] * Math::PI / 180
      lat2 = b[1] * Math::PI / 180
      d_lat = lat2 - lat1
      d_lon = (b[0] - a[0]) * Math::PI / 180
      h = Math.sin(d_lat / 2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(d_lon / 2)**2
      2 * r * Math.asin(Math.sqrt(h))
    end
  end
end
