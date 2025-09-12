# frozen_string_literal: true

class HexagonQuery
  # Maximum number of hexagons to return in a single request
  MAX_HEXAGONS_PER_REQUEST = 5000

  attr_reader :min_lon, :min_lat, :max_lon, :max_lat, :hex_size, :user_id, :start_date, :end_date

  def initialize(min_lon:, min_lat:, max_lon:, max_lat:, hex_size:, user_id: nil, start_date: nil, end_date: nil)
    @min_lon = min_lon
    @min_lat = min_lat
    @max_lon = max_lon
    @max_lat = max_lat
    @hex_size = hex_size
    @user_id = user_id
    @start_date = start_date
    @end_date = end_date
  end

  def call
    ActiveRecord::Base.connection.execute(build_hexagon_sql)
  end

  private

  def build_hexagon_sql
    user_filter = user_id ? "user_id = #{user_id}" : '1=1'
    date_filter = build_date_filter

    <<~SQL
      WITH bbox_geom AS (
        SELECT ST_MakeEnvelope(#{min_lon}, #{min_lat}, #{max_lon}, #{max_lat}, 4326) as geom
      ),
      bbox_utm AS (
        SELECT
          ST_Transform(geom, 3857) as geom_utm,
          geom as geom_wgs84
        FROM bbox_geom
      ),
      user_points AS (
        SELECT
          lonlat::geometry as point_geom,
          ST_Transform(lonlat::geometry, 3857) as point_geom_utm,
          id,
          timestamp
        FROM points
        WHERE #{user_filter}
          #{date_filter}
          AND ST_Intersects(
            lonlat::geometry,
            (SELECT geom FROM bbox_geom)
          )
      ),
      hex_grid AS (
        SELECT
          (ST_HexagonGrid(#{hex_size}, bbox_utm.geom_utm)).geom as hex_geom_utm,
          (ST_HexagonGrid(#{hex_size}, bbox_utm.geom_utm)).i as hex_i,
          (ST_HexagonGrid(#{hex_size}, bbox_utm.geom_utm)).j as hex_j
        FROM bbox_utm
      ),
      hexagons_with_points AS (
        SELECT DISTINCT
          hex_geom_utm,
          hex_i,
          hex_j
        FROM hex_grid hg
        INNER JOIN user_points up ON ST_Intersects(hg.hex_geom_utm, up.point_geom_utm)
      ),
      hexagon_stats AS (
        SELECT
          hwp.hex_geom_utm,
          hwp.hex_i,
          hwp.hex_j,
          COUNT(up.id) as point_count,
          MIN(up.timestamp) as earliest_point,
          MAX(up.timestamp) as latest_point
        FROM hexagons_with_points hwp
        INNER JOIN user_points up ON ST_Intersects(hwp.hex_geom_utm, up.point_geom_utm)
        GROUP BY hwp.hex_geom_utm, hwp.hex_i, hwp.hex_j
      )
      SELECT
        ST_AsGeoJSON(ST_Transform(hex_geom_utm, 4326)) as geojson,
        hex_i,
        hex_j,
        point_count,
        earliest_point,
        latest_point,
        row_number() OVER (ORDER BY point_count DESC) as id
      FROM hexagon_stats
      ORDER BY point_count DESC
      LIMIT #{MAX_HEXAGONS_PER_REQUEST};
    SQL
  end

  def build_date_filter
    return '' unless start_date || end_date

    conditions = []
    conditions << "timestamp >= EXTRACT(EPOCH FROM '#{start_date}'::timestamp)" if start_date
    conditions << "timestamp <= EXTRACT(EPOCH FROM '#{end_date}'::timestamp)" if end_date

    conditions.any? ? "AND #{conditions.join(' AND ')}" : ''
  end
end