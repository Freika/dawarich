# frozen_string_literal: true

module Maps
  class H3HexagonCalculator
    def initialize(user_id, start_date, end_date, h3_resolution = 8)
      @user_id = user_id
      @start_date = start_date
      @end_date = end_date
      @h3_resolution = h3_resolution
    end

    def call
      user_points = fetch_user_points
      return { success: false, error: 'No points found for the given date range' } if user_points.empty?

      h3_indexes = calculate_h3_indexes(user_points)
      hexagon_features = build_hexagon_features(h3_indexes)

      {
        success: true,
        data: {
          type: 'FeatureCollection',
          features: hexagon_features
        }
      }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    private

    attr_reader :user_id, :start_date, :end_date, :h3_resolution

    def fetch_user_points
      Point.without_raw_data
           .where(user_id: user_id)
           .where(timestamp: start_date.to_i..end_date.to_i)
           .where.not(lonlat: nil)
           .select(:id, :lonlat, :timestamp)
    end

    def calculate_h3_indexes(points)
      h3_counts = Hash.new(0)

      points.find_each do |point|
        # Convert PostGIS point to lat/lng array: [lat, lng]
        coordinates = [point.lonlat.y, point.lonlat.x]

        # Get H3 index for these coordinates at specified resolution
        h3_index = H3.from_geo_coordinates(coordinates, h3_resolution)

        # Count points in each hexagon
        h3_counts[h3_index] += 1
      end

      h3_counts
    end

    def build_hexagon_features(h3_counts)
      h3_counts.map do |h3_index, point_count|
        # Get the boundary coordinates for this H3 hexagon
        boundary_coordinates = H3.to_boundary(h3_index)

        # Convert to GeoJSON polygon format (lng, lat)
        polygon_coordinates = boundary_coordinates.map { |lat, lng| [lng, lat] }

        # Close the polygon by adding the first point at the end
        polygon_coordinates << polygon_coordinates.first

        {
          type: 'Feature',
          geometry: {
            type: 'Polygon',
            coordinates: [polygon_coordinates]
          },
          properties: {
            h3_index: h3_index.to_s(16),
            point_count: point_count,
            center: H3.to_geo_coordinates(h3_index)
          }
        }
      end
    end
  end
end
