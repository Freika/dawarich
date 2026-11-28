# frozen_string_literal: true

module TileCoordinates
  class InvalidTileCoordinatesError < StandardError; end

  MAX_ZOOM = 22

  private

  def parse_integer(value)
    return value if value.is_a?(Integer)

    Integer(value, 10)
  rescue ArgumentError, TypeError
    raise InvalidTileCoordinatesError
  end

  def validate_tile_coordinates!
    raise InvalidTileCoordinatesError if z.negative? || z > MAX_ZOOM

    max_index = (1 << z) - 1
    raise InvalidTileCoordinatesError if x.negative? || y.negative?
    raise InvalidTileCoordinatesError if x > max_index || y > max_index
  end
end
