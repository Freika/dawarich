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
    binds = []
    user_sql = build_user_filter(binds)
    date_filter = build_date_filter(binds)

    sql = build_hexagon_sql(user_sql, date_filter)

    ActiveRecord::Base.connection.exec_query(sql, 'hexagon_sql', binds)
  end

  private

  def build_hexagon_sql(user_sql, date_filter)
    <<~SQL
      WITH bbox_geom AS (
        SELECT ST_MakeEnvelope($1, $2, $3, $4, 4326) as geom
      ),
      bbox_utm AS (
        SELECT ST_Transform(geom, 3857) as geom_utm FROM bbox_geom
      ),
      user_points AS (
        SELECT
          lonlat::geometry as point_geom,
          ST_Transform(lonlat::geometry, 3857) as point_geom_utm,
          id,
          timestamp
        FROM points
        WHERE #{user_sql}
          #{date_filter}
          AND lonlat && (SELECT geom FROM bbox_geom)
      ),
      hex_grid AS (
        SELECT
          (ST_HexagonGrid($5, geom_utm)).geom as hex_geom_utm,
          (ST_HexagonGrid($5, geom_utm)).i as hex_i,
          (ST_HexagonGrid($5, geom_utm)).j as hex_j
        FROM bbox_utm
      ),
      hexagons_with_points AS (
        SELECT DISTINCT
          hg.hex_geom_utm,
          hg.hex_i,
          hg.hex_j
        FROM hex_grid hg
        JOIN user_points up ON ST_Intersects(hg.hex_geom_utm, up.point_geom_utm)
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
        JOIN user_points up ON ST_Intersects(hwp.hex_geom_utm, up.point_geom_utm)
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
      LIMIT $6;
    SQL
  end

  def build_user_filter(binds)
    # Add bbox coordinates: min_lon, min_lat, max_lon, max_lat
    binds << min_lon
    binds << min_lat
    binds << max_lon
    binds << max_lat

    # Add hex_size
    binds << hex_size

    # Add limit
    binds << MAX_HEXAGONS_PER_REQUEST

    if user_id
      binds << user_id
      'user_id = $7'
    else
      '1=1'
    end
  end

  def build_date_filter(binds)
    return '' unless start_date || end_date

    conditions = []
    current_param_index = user_id ? 8 : 7 # Account for bbox, hex_size, limit, and potential user_id

    if start_date
      start_timestamp = parse_date_to_timestamp(start_date)
      binds << start_timestamp
      conditions << "timestamp >= $#{current_param_index}"
      current_param_index += 1
    end

    if end_date
      end_timestamp = parse_date_to_timestamp(end_date)
      binds << end_timestamp
      conditions << "timestamp <= $#{current_param_index}"
    end

    conditions.any? ? "AND #{conditions.join(' AND ')}" : ''
  end

  def parse_date_to_timestamp(date_string)
    # Convert ISO date string to timestamp integer
    Time.parse(date_string).to_i
  rescue ArgumentError => e
    ExceptionReporter.call(e, "Invalid date format: #{date_string}")
    raise ArgumentError, "Invalid date format: #{date_string}"
  end
end
