# frozen_string_literal: true

module Maps
  class HexagonPolygonGenerator
    DEFAULT_SIZE_METERS = 1000

    def self.call(center_lng:, center_lat:, size_meters: DEFAULT_SIZE_METERS)
      new(center_lng: center_lng, center_lat: center_lat, size_meters: size_meters).call
    end

    def initialize(center_lng:, center_lat:, size_meters: DEFAULT_SIZE_METERS)
      @center_lng = center_lng
      @center_lat = center_lat
      @size_meters = size_meters
    end

    def call
      generate_hexagon_polygon
    end

    private

    attr_reader :center_lng, :center_lat, :size_meters

    def generate_hexagon_polygon
      # Generate hexagon vertices around center point
      # PostGIS ST_HexagonGrid uses size_meters as the edge-to-edge distance (width/flat-to-flat)
      # For a regular hexagon with width = size_meters:
      # - Width (edge to edge) = size_meters
      # - Radius (center to vertex) = width / √3 ≈ size_meters * 0.577
      # - Edge length ≈ radius ≈ size_meters * 0.577

      radius_meters = size_meters / Math.sqrt(2.7) # Convert width to radius

      # Convert meter radius to degrees (rough approximation)
      # 1 degree latitude ≈ 111,111 meters
      # 1 degree longitude ≈ 111,111 * cos(latitude) meters
      lat_degree_in_meters = 111_111.0
      lng_degree_in_meters = lat_degree_in_meters * Math.cos(center_lat * Math::PI / 180)

      radius_lat_degrees = radius_meters / lat_degree_in_meters
      radius_lng_degrees = radius_meters / lng_degree_in_meters

      vertices = build_vertices(radius_lat_degrees, radius_lng_degrees)

      {
        'type' => 'Polygon',
        'coordinates' => [vertices]
      }
    end

    def build_vertices(radius_lat_degrees, radius_lng_degrees)
      vertices = []
      6.times do |i|
        # Calculate angle for each vertex (60 degrees apart, starting from 0)
        angle = (i * 60) * Math::PI / 180

        # Calculate vertex position
        lat_offset = radius_lat_degrees * Math.sin(angle)
        lng_offset = radius_lng_degrees * Math.cos(angle)

        vertices << [center_lng + lng_offset, center_lat + lat_offset]
      end

      # Close the polygon by adding the first vertex at the end
      vertices << vertices.first
      vertices
    end
  end
end