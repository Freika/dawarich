# frozen_string_literal: true

class Maps::HexagonCenters
  include ActiveModel::Validations

  # Constants for configuration
  HEX_SIZE = 1000 # meters - fixed 1000m hexagons
  MAX_AREA_KM2 = 10_000 # Maximum area for simple calculation
  TILE_SIZE_KM = 100 # Size of each tile for large area processing
  MAX_TILES = 100 # Maximum number of tiles to process

  # Validation error classes
  class BoundingBoxTooLargeError < StandardError; end
  class InvalidCoordinatesError < StandardError; end
  class PostGISError < StandardError; end

  attr_reader :user_id, :start_date, :end_date

  validates :user_id, presence: true

  def initialize(user_id:, start_date:, end_date:)
    @user_id = user_id
    @start_date = start_date
    @end_date = end_date
  end

  def call
    validate!

    bounds = calculate_data_bounds
    return nil unless bounds

    # Check if area requires tiled processing
    area_km2 = calculate_bounding_box_area(bounds)
    if area_km2 > MAX_AREA_KM2
      Rails.logger.info "Large area detected (#{area_km2.round} km²), using tiled processing for user #{user_id}"
      return calculate_hexagon_centers_tiled(bounds, area_km2)
    end

    calculate_hexagon_centers_simple
  rescue ActiveRecord::StatementInvalid => e
    message = "Failed to calculate hexagon centers: #{e.message}"
    ExceptionReporter.call(e, message)
    raise PostGISError, message
  end

  private

  def calculate_data_bounds
    start_timestamp = parse_date_to_timestamp(start_date)
    end_timestamp = parse_date_to_timestamp(end_date)

    bounds_result = ActiveRecord::Base.connection.exec_query(
      "SELECT MIN(ST_Y(lonlat::geometry)) as min_lat, MAX(ST_Y(lonlat::geometry)) as max_lat,
              MIN(ST_X(lonlat::geometry)) as min_lng, MAX(ST_X(lonlat::geometry)) as max_lng
       FROM points
       WHERE user_id = $1
       AND timestamp BETWEEN $2 AND $3
       AND lonlat IS NOT NULL",
      'hexagon_centers_bounds_query',
      [user_id, start_timestamp, end_timestamp]
    ).first

    return nil unless bounds_result

    {
      min_lat: bounds_result['min_lat'].to_f,
      max_lat: bounds_result['max_lat'].to_f,
      min_lng: bounds_result['min_lng'].to_f,
      max_lng: bounds_result['max_lng'].to_f
    }
  end

  def calculate_bounding_box_area(bounds)
    width = (bounds[:max_lng] - bounds[:min_lng]).abs
    height = (bounds[:max_lat] - bounds[:min_lat]).abs

    # Convert degrees to approximate kilometers
    avg_lat = (bounds[:min_lat] + bounds[:max_lat]) / 2
    width_km = width * 111 * Math.cos(avg_lat * Math::PI / 180)
    height_km = height * 111

    width_km * height_km
  end

  def calculate_hexagon_centers_simple
    start_timestamp = parse_date_to_timestamp(start_date)
    end_timestamp = parse_date_to_timestamp(end_date)

    sql = <<~SQL
      WITH bbox_geom AS (
        SELECT ST_SetSRID(ST_Envelope(ST_Collect(lonlat::geometry)), 4326) as geom
        FROM points
        WHERE user_id = $1
        AND timestamp BETWEEN $2 AND $3
        AND lonlat IS NOT NULL
      ),
      bbox_utm AS (
        SELECT ST_Transform(geom, 3857) as geom_utm FROM bbox_geom
      ),
      user_points AS (
        SELECT
          lonlat::geometry as point_geom,
          ST_Transform(lonlat::geometry, 3857) as point_geom_utm,
          timestamp
        FROM points
        WHERE user_id = $1
        AND timestamp BETWEEN $2 AND $3
        AND lonlat IS NOT NULL
      ),
      hex_grid AS (
        SELECT
          (ST_HexagonGrid($4, geom_utm)).geom as hex_geom_utm,
          (ST_HexagonGrid($4, geom_utm)).i as hex_i,
          (ST_HexagonGrid($4, geom_utm)).j as hex_j
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
      hexagon_centers AS (
        SELECT
          ST_Transform(ST_Centroid(hwp.hex_geom_utm), 4326) as center,
          MIN(up.timestamp) as earliest_point,
          MAX(up.timestamp) as latest_point
        FROM hexagons_with_points hwp
        JOIN user_points up ON ST_Intersects(hwp.hex_geom_utm, up.point_geom_utm)
        GROUP BY hwp.hex_geom_utm, hwp.hex_i, hwp.hex_j
      )
      SELECT
        ST_X(center) as lng,
        ST_Y(center) as lat,
        earliest_point,
        latest_point
      FROM hexagon_centers
      ORDER BY earliest_point;
    SQL

    result = ActiveRecord::Base.connection.exec_query(
      sql,
      'hexagon_centers_calculation',
      [user_id, start_timestamp, end_timestamp, HEX_SIZE]
    )

    result.map do |row|
      [
        row['lng'].to_f,
        row['lat'].to_f,
        row['earliest_point']&.to_i,
        row['latest_point']&.to_i
      ]
    end
  end

  def calculate_hexagon_centers_tiled(bounds, area_km2)
    # Calculate optimal tile size based on area
    tiles = generate_tiles(bounds, area_km2)

    if tiles.size > MAX_TILES
      Rails.logger.warn "Area too large even for tiling (#{tiles.size} tiles), using sampling approach"
      return calculate_hexagon_centers_sampled(bounds, area_km2)
    end

    Rails.logger.info "Processing #{tiles.size} tiles for large area hexagon calculation"

    all_centers = []
    tiles.each_with_index do |tile, index|
      Rails.logger.debug "Processing tile #{index + 1}/#{tiles.size}"

      centers = calculate_hexagon_centers_for_tile(tile)
      all_centers.concat(centers) if centers.any?
    end

    # Remove duplicates and sort by timestamp
    deduplicate_and_sort_centers(all_centers)
  end

  def generate_tiles(bounds, area_km2)
    # Calculate number of tiles needed
    tiles_needed = (area_km2 / (TILE_SIZE_KM * TILE_SIZE_KM)).ceil
    tiles_per_side = Math.sqrt(tiles_needed).ceil

    lat_step = (bounds[:max_lat] - bounds[:min_lat]) / tiles_per_side
    lng_step = (bounds[:max_lng] - bounds[:min_lng]) / tiles_per_side

    tiles = []
    tiles_per_side.times do |i|
      tiles_per_side.times do |j|
        tile_bounds = {
          min_lat: bounds[:min_lat] + (i * lat_step),
          max_lat: bounds[:min_lat] + ((i + 1) * lat_step),
          min_lng: bounds[:min_lng] + (j * lng_step),
          max_lng: bounds[:min_lng] + ((j + 1) * lng_step)
        }
        tiles << tile_bounds
      end
    end

    tiles
  end

  def calculate_hexagon_centers_for_tile(tile_bounds)
    start_timestamp = parse_date_to_timestamp(start_date)
    end_timestamp = parse_date_to_timestamp(end_date)

    sql = <<~SQL
      WITH tile_bounds AS (
        SELECT ST_MakeEnvelope($1, $2, $3, $4, 4326) as geom
      ),
      tile_utm AS (
        SELECT ST_Transform(geom, 3857) as geom_utm FROM tile_bounds
      ),
      user_points AS (
        SELECT
          lonlat::geometry as point_geom,
          ST_Transform(lonlat::geometry, 3857) as point_geom_utm,
          timestamp
        FROM points
        WHERE user_id = $5
        AND timestamp BETWEEN $6 AND $7
        AND lonlat IS NOT NULL
        AND lonlat && (SELECT geom FROM tile_bounds)
      ),
      hex_grid AS (
        SELECT
          (ST_HexagonGrid($8, geom_utm)).geom as hex_geom_utm,
          (ST_HexagonGrid($8, geom_utm)).i as hex_i,
          (ST_HexagonGrid($8, geom_utm)).j as hex_j
        FROM tile_utm
      ),
      hexagons_with_points AS (
        SELECT DISTINCT
          hg.hex_geom_utm,
          hg.hex_i,
          hg.hex_j
        FROM hex_grid hg
        JOIN user_points up ON ST_Intersects(hg.hex_geom_utm, up.point_geom_utm)
      ),
      hexagon_centers AS (
        SELECT
          ST_Transform(ST_Centroid(hwp.hex_geom_utm), 4326) as center,
          MIN(up.timestamp) as earliest_point,
          MAX(up.timestamp) as latest_point
        FROM hexagons_with_points hwp
        JOIN user_points up ON ST_Intersects(hwp.hex_geom_utm, up.point_geom_utm)
        GROUP BY hwp.hex_geom_utm, hwp.hex_i, hwp.hex_j
      )
      SELECT
        ST_X(center) as lng,
        ST_Y(center) as lat,
        earliest_point,
        latest_point
      FROM hexagon_centers;
    SQL

    result = ActiveRecord::Base.connection.exec_query(
      sql,
      'hexagon_centers_tile_calculation',
      [
        tile_bounds[:min_lng], tile_bounds[:min_lat],
        tile_bounds[:max_lng], tile_bounds[:max_lat],
        user_id, start_timestamp, end_timestamp, HEX_SIZE
      ]
    )

    result.map do |row|
      [
        row['lng'].to_f,
        row['lat'].to_f,
        row['earliest_point']&.to_i,
        row['latest_point']&.to_i
      ]
    end
  end

  def calculate_hexagon_centers_sampled(bounds, area_km2)
    # For extremely large areas, use point density sampling
    Rails.logger.info "Using density-based sampling for extremely large area (#{area_km2.round} km²)"

    start_timestamp = parse_date_to_timestamp(start_date)
    end_timestamp = parse_date_to_timestamp(end_date)

    # Get point density distribution
    sql = <<~SQL
      WITH density_grid AS (
        SELECT
          ST_SnapToGrid(lonlat::geometry, 0.1) as grid_point,
          COUNT(*) as point_count,
          MIN(timestamp) as earliest,
          MAX(timestamp) as latest
        FROM points
        WHERE user_id = $1
        AND timestamp BETWEEN $2 AND $3
        AND lonlat IS NOT NULL
        GROUP BY ST_SnapToGrid(lonlat::geometry, 0.1)
        HAVING COUNT(*) >= 5
      ),
      sampled_points AS (
        SELECT
          ST_X(grid_point) as lng,
          ST_Y(grid_point) as lat,
          earliest,
          latest
        FROM density_grid
        ORDER BY point_count DESC
        LIMIT 1000
      )
      SELECT lng, lat, earliest, latest FROM sampled_points;
    SQL

    result = ActiveRecord::Base.connection.exec_query(
      sql,
      'hexagon_centers_sampled_calculation',
      [user_id, start_timestamp, end_timestamp]
    )

    result.map do |row|
      [
        row['lng'].to_f,
        row['lat'].to_f,
        row['earliest']&.to_i,
        row['latest']&.to_i
      ]
    end
  end

  def deduplicate_and_sort_centers(centers)
    # Remove near-duplicate centers (within ~100m)
    precision = 3 # ~111m precision at equator
    unique_centers = {}

    centers.each do |center|
      lng, lat, earliest, latest = center
      key = "#{lng.round(precision)},#{lat.round(precision)}"

      if unique_centers[key]
        # Keep the one with earlier timestamp or merge timestamps
        existing = unique_centers[key]
        unique_centers[key] = [
          lng, lat,
          [earliest, existing[2]].compact.min,
          [latest, existing[3]].compact.max
        ]
      else
        unique_centers[key] = center
      end
    end

    unique_centers.values.sort_by { |center| center[2] || 0 }
  end

  def parse_date_to_timestamp(date)
    case date
    when String
      if date.match?(/^\d+$/)
        date.to_i
      else
        Time.parse(date).to_i
      end
    when Integer
      date
    else
      Time.parse(date.to_s).to_i
    end
  rescue ArgumentError => e
    ExceptionReporter.call(e, "Invalid date format: #{date}")
    raise ArgumentError, "Invalid date format: #{date}"
  end

  def validate!
    return if valid?

    raise InvalidCoordinatesError, errors.full_messages.join(', ')
  end
end
