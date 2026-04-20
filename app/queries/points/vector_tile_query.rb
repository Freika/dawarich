# frozen_string_literal: true

class Points::VectorTileQuery
  class InvalidTileCoordinatesError < StandardError; end

  EXTENT = 4096
  BUFFER = 256
  LAYER_NAME = 'points'

  def initialize(scope:, z:, x:, y:)
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
    Point.sanitize_sql_array(
      [
        <<~SQL.squish,
          WITH bounds AS (
            SELECT
              ST_TileEnvelope(?, ?, ?) AS geom_3857,
              ST_Transform(ST_TileEnvelope(?, ?, ?), 4326) AS geom_4326
          ),
          points_in_tile AS (
            SELECT
              points.id::text AS point_id,
              points.timestamp::text AS timestamp,
              points.battery::text AS battery,
              points.altitude::text AS altitude,
              points.velocity::text AS velocity,
              points.track_id::text AS track_id,
              points.visit_id::text AS visit_id,
              ST_AsMVTGeom(
                ST_Transform(points.lonlat::geometry, 3857),
                bounds.geom_3857,
                #{EXTENT},
                #{BUFFER},
                true
              ) AS geom
            FROM (#{tile_scope.to_sql}) AS points
            CROSS JOIN bounds
            WHERE points.lonlat IS NOT NULL
              AND ST_Intersects(points.lonlat::geometry, bounds.geom_4326)
          )
          SELECT ST_AsMVT(points_in_tile.*, ?, #{EXTENT}, 'geom')
          FROM points_in_tile
          WHERE geom IS NOT NULL
        SQL
        z, x, y, z, x, y, LAYER_NAME
      ]
    )
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
