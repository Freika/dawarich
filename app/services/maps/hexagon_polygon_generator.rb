# frozen_string_literal: true

module Maps
  class HexagonPolygonGenerator
    def initialize(h3_index:)
      @h3_index = h3_index
    end

    def call
      # Parse H3 index from hex string if needed
      index = h3_index.is_a?(String) ? h3_index.to_i(16) : h3_index

      # Get the boundary coordinates for this H3 hexagon
      boundary_coordinates = H3.to_boundary(index)

      # Convert to GeoJSON polygon format (lng, lat)
      polygon_coordinates = boundary_coordinates.map { [_2, _1] }

      # Close the polygon by adding the first point at the end
      polygon_coordinates << polygon_coordinates.first

      {
        'type' => 'Polygon',
        'coordinates' => [polygon_coordinates]
      }
    end

    private

    attr_reader :h3_index
  end
end
