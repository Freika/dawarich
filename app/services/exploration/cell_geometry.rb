# frozen_string_literal: true

module Exploration
  class CellGeometry
    RESOLUTION = 9

    def self.id(lat, lon)
      H3.from_geo_coordinates([lat, lon], RESOLUTION).to_s(16)
    end

    # Unwrap each edge before splitting at the antimeridian. For a cell
    # containing a pole, the ring also follows the edge of the projection.
    def self.geojson(id)
      vertices = H3.to_boundary(id.to_i(16)).map { |lat, lon| [lon, lat] }
      ring = [vertices.first]
      vertices.drop(1).each { |lon, lat| ring << [unwrap(lon, ring.last[0]), lat] }
      closing_lon = unwrap(vertices.first[0], ring.last[0])
      if (closing_lon - ring.first[0]).abs > 180
        pole = vertices.sum(&:last).positive? ? 90 : -90
        ring.concat([[closing_lon, ring.first[1]], [closing_lon, pole], [ring.first[0], pole]])
      end
      ring << ring.first
      { type: 'Polygon', coordinates: [ring] }
    end

    def self.unwrap(lon, previous)
      lon -= 360 while lon - previous > 180
      lon += 360 while lon - previous < -180
      lon
    end
  end
end
