# frozen_string_literal: true

module Maps
  class HexagonPolygonGenerator
    def initialize(center_lng: nil, center_lat: nil, h3_resolution: 5, h3_index: nil)
      @center_lng = center_lng
      @center_lat = center_lat
      @h3_resolution = h3_resolution
      @h3_index = h3_index
    end

    def call
      generate_h3_hexagon_polygon
    end

    private

    attr_reader :center_lng, :center_lat, :h3_resolution, :h3_index

    def generate_h3_hexagon_polygon
      # Convert coordinates to H3 format [lat, lng]
      coordinates = [center_lat, center_lng]

      # Get H3 index for these coordinates at specified resolution
      h3_index = H3.from_geo_coordinates(coordinates, h3_resolution)

      # Get the boundary coordinates for this H3 hexagon
      boundary_coordinates = H3.to_boundary(h3_index)

      # Convert to GeoJSON polygon format (lng, lat)
      polygon_coordinates = boundary_coordinates.map { [_2, _1] }

      # Close the polygon by adding the first point at the end
      polygon_coordinates << polygon_coordinates.first

      {
        'type' => 'Polygon',
        'coordinates' => [polygon_coordinates]
      }
    end
  end
end
