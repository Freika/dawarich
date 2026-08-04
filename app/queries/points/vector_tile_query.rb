# frozen_string_literal: true

class Points::VectorTileQuery
  class InvalidTileCoordinatesError < StandardError; end

  EXTENT = 4096
  BUFFER = 256
  # Candidate rows must cover the ST_AsMVTGeom buffer, or markers clip at tile seams
  MARGIN = (BUFFER.to_f / EXTENT)
  # Below this zoom the envelope is large enough that its geodetic bounding box
  # no longer contains the planar rectangle, which would silently drop points
  MIN_PREFILTER_ZOOM = 5
  LAYER_NAME = 'points'

  def initialize(scope:, z:, x:, y:) # rubocop:disable Naming/MethodParameterName
    @scope = scope
    @z = parse_integer(z)
    @x = parse_integer(x)
    @y = parse_integer(y)
  end

  def call
    validate_tile_coordinates!

    Point.connection.select_value(sql)
  end

  private

  attr_reader :scope, :z, :x, :y

  def sql
    Point.sanitize_sql_array([sql_template, *bind_values])
  end

  def sql_template
    <<~SQL.squish
      WITH points_in_tile AS (
        SELECT
          points.id AS id,
          points.timestamp AS timestamp,
          points.battery AS battery,
          points.altitude AS altitude,
          points.velocity AS velocity,
          points.track_id AS track_id,
          points.visit_id AS visit_id,
          ST_AsMVTGeom(
            ST_Transform(points.lonlat::geometry, 3857),
            ST_TileEnvelope(?, ?, ?),
            #{EXTENT},
            #{BUFFER},
            true
          ) AS geom
        FROM (#{tile_scope.to_sql}) AS points
        WHERE points.lonlat IS NOT NULL
          #{spatial_prefilter}
          AND ST_Intersects(
            points.lonlat::geometry,
            ST_Transform(ST_TileEnvelope(?, ?, ?, margin => #{MARGIN}), 4326)
          )
        ORDER BY points.id
      )
      SELECT ST_AsMVT(points_in_tile.*, ?, #{EXTENT}, 'geom')
      FROM points_in_tile
      WHERE geom IS NOT NULL
    SQL
  end

  # lonlat is geography, so the planar test alone cannot use the GiST index
  def spatial_prefilter
    return '' if z < MIN_PREFILTER_ZOOM

    "AND points.lonlat && ST_Transform(ST_TileEnvelope(?, ?, ?, margin => #{MARGIN}), 4326)::geography"
  end

  def bind_values
    values = [z, x, y]
    values += [z, x, y] if z >= MIN_PREFILTER_ZOOM
    values + [z, x, y, LAYER_NAME]
  end

  def tile_scope
    scope.except(:select, :order, :includes, :preload, :eager_load)
         .select(:id, :timestamp, :battery, :altitude, :velocity, :track_id, :visit_id, :lonlat)
  end

  def parse_integer(value)
    Integer(value, 10)
  rescue ArgumentError, TypeError
    raise InvalidTileCoordinatesError
  end

  def validate_tile_coordinates!
    raise InvalidTileCoordinatesError if z.negative? || z > 22

    max_index = (1 << z) - 1
    raise InvalidTileCoordinatesError if x.negative? || y.negative?
    raise InvalidTileCoordinatesError if x > max_index || y > max_index
  end
end
