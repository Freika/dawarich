# frozen_string_literal: true

module Maps
  class HexagonPolygonGenerator
    DEFAULT_SIZE_METERS = 1000

    def self.call(center_lng:, center_lat:, size_meters: DEFAULT_SIZE_METERS, use_h3: false, h3_resolution: 5)
      new(
        center_lng: center_lng,
        center_lat: center_lat,
        size_meters: size_meters,
        use_h3: use_h3,
        h3_resolution: h3_resolution
      ).call
    end

    def initialize(center_lng:, center_lat:, size_meters: DEFAULT_SIZE_METERS, use_h3: false, h3_resolution: 5)
      @center_lng = center_lng
      @center_lat = center_lat
      @size_meters = size_meters
      @use_h3 = use_h3
      @h3_resolution = h3_resolution
    end

    def call
      if use_h3
        generate_h3_hexagon_polygon
      else
        generate_hexagon_polygon
      end
    end

    private

    attr_reader :center_lng, :center_lat, :size_meters, :use_h3, :h3_resolution

    def generate_h3_hexagon_polygon
      # Convert coordinates to H3 format [lat, lng]
      coordinates = [center_lat, center_lng]

      # Get H3 index for these coordinates at specified resolution
      h3_index = H3.from_geo_coordinates(coordinates, h3_resolution)

      # Get the boundary coordinates for this H3 hexagon
      boundary_coordinates = H3.to_boundary(h3_index)

      # Convert to GeoJSON polygon format (lng, lat)
      polygon_coordinates = boundary_coordinates.map { |lat, lng| [lng, lat] }

      # Close the polygon by adding the first point at the end
      polygon_coordinates << polygon_coordinates.first

      {
        'type' => 'Polygon',
        'coordinates' => [polygon_coordinates]
      }
    end

    def generate_hexagon_polygon
      # Generate hexagon vertices around center point
      # For a regular hexagon:
      # - Circumradius (center to vertex) = size_meters / 2
      # - This creates hexagons that are approximately size_meters wide

      radius_meters = size_meters / 2.0

      # Convert meter radius to degrees
      # 1 degree latitude ≈ 111,111 meters
      # 1 degree longitude ≈ 111,111 * cos(latitude) meters at given latitude
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
        # Start at 30 degrees to orient hexagon with flat top
        angle = ((i * 60) + 30) * Math::PI / 180

        # Calculate vertex position using proper geographic coordinate system
        # longitude (x-axis) uses cosine, latitude (y-axis) uses sine
        lng_offset = radius_lng_degrees * Math.cos(angle)
        lat_offset = radius_lat_degrees * Math.sin(angle)

        vertices << [center_lng + lng_offset, center_lat + lat_offset]
      end

      # Close the polygon by adding the first vertex at the end
      vertices << vertices.first
      vertices
    end
  end
end
