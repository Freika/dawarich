# frozen_string_literal: true

class Maps::HexagonGrid
  include ActiveModel::Validations

  # Constants for configuration
  DEFAULT_HEX_SIZE = 500 # meters (center to edge)
  TARGET_HEX_EDGE_PX = 20 # pixels (edge length target)
  MAX_HEXAGONS_PER_REQUEST = 5000
  MAX_AREA_KM2 = 250_000 # 500km x 500km

  # Validation error classes
  class BoundingBoxTooLargeError < StandardError; end
  class InvalidCoordinatesError < StandardError; end
  class PostGISError < StandardError; end

  attr_reader :min_lon, :min_lat, :max_lon, :max_lat, :hex_size, :user_id, :start_date, :end_date, :viewport_width, :viewport_height

  validates :min_lon, :max_lon, inclusion: { in: -180..180 }
  validates :min_lat, :max_lat, inclusion: { in: -90..90 }
  validates :hex_size, numericality: { greater_than: 0 }

  validate :validate_bbox_order
  validate :validate_area_size

  def initialize(params = {})
    @min_lon = params[:min_lon].to_f
    @min_lat = params[:min_lat].to_f
    @max_lon = params[:max_lon].to_f
    @max_lat = params[:max_lat].to_f
    @viewport_width = params[:viewport_width]&.to_f
    @viewport_height = params[:viewport_height]&.to_f
    @hex_size = calculate_dynamic_hex_size(params)
    @user_id = params[:user_id]
    @start_date = params[:start_date]
    @end_date = params[:end_date]
  end

  def call
    validate!
    generate_hexagons
  end

  def area_km2
    @area_km2 ||= calculate_area_km2
  end

  def crosses_dateline?
    min_lon > max_lon
  end

  def in_polar_region?
    max_lat.abs > 85 || min_lat.abs > 85
  end

  def estimated_hexagon_count
    # Rough estimation based on area
    # A 500m radius hexagon covers approximately 0.65 km²
    hexagon_area_km2 = 0.65 * (hex_size / 500.0) ** 2
    (area_km2 / hexagon_area_km2).round
  end

  private

  def calculate_dynamic_hex_size(params)
    # If viewport dimensions are provided, calculate hex_size for 20px edge length
    if viewport_width && viewport_height && viewport_width > 0 && viewport_height > 0
      # Calculate the geographic width of the bounding box in meters
      avg_lat = (min_lat + max_lat) / 2
      bbox_width_degrees = (max_lon - min_lon).abs
      bbox_width_meters = bbox_width_degrees * 111_320 * Math.cos(avg_lat * Math::PI / 180)
      
      # Calculate how many meters per pixel based on current viewport span (zoom-independent)
      meters_per_pixel = bbox_width_meters / viewport_width
      
      # For a regular hexagon, the edge length is approximately 0.866 times the radius (center to vertex)
      # So if we want a 20px edge, we need: edge_length_meters = 20 * meters_per_pixel
      # And radius = edge_length / 0.866
      edge_length_meters = TARGET_HEX_EDGE_PX * meters_per_pixel
      hex_radius_meters = edge_length_meters / 0.866
      
      # Clamp to reasonable bounds to prevent excessive computation
      calculated_size = hex_radius_meters.clamp(50, 10_000)
      
      Rails.logger.debug "Dynamic hex size calculation: bbox_width=#{bbox_width_meters.round}m, viewport=#{viewport_width}px, meters_per_pixel=#{meters_per_pixel.round(2)}, hex_size=#{calculated_size.round}m"
      
      calculated_size
    else
      # Fallback to provided hex_size or default
      fallback_size = params[:hex_size]&.to_f || DEFAULT_HEX_SIZE
      Rails.logger.debug "Using fallback hex size: #{fallback_size}m (no viewport dimensions provided)"
      fallback_size
    end
  end

  def validate_bbox_order
    errors.add(:base, 'min_lon must be less than max_lon') if min_lon >= max_lon
    errors.add(:base, 'min_lat must be less than max_lat') if min_lat >= max_lat
  end

  def validate_area_size
    if area_km2 > MAX_AREA_KM2
      errors.add(:base, "Area too large (#{area_km2.round} km²). Maximum allowed: #{MAX_AREA_KM2} km²")
    end
  end

  def calculate_area_km2
    width = (max_lon - min_lon).abs
    height = (max_lat - min_lat).abs

    # Convert degrees to approximate kilometers
    # 1 degree latitude ≈ 111 km
    # 1 degree longitude ≈ 111 km * cos(latitude)
    avg_lat = (min_lat + max_lat) / 2
    width_km = width * 111 * Math.cos(avg_lat * Math::PI / 180)
    height_km = height * 111

    width_km * height_km
  end

  def generate_hexagons
    sql = build_hexagon_sql

    Rails.logger.debug "Generating hexagons for bbox: #{[min_lon, min_lat, max_lon, max_lat]}"
    Rails.logger.debug "Estimated hexagon count: #{estimated_hexagon_count}"

    result = execute_sql(sql)
    format_hexagons(result)
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error "PostGIS error generating hexagons: #{e.message}"
    raise PostGISError, "Failed to generate hexagon grid: #{e.message}"
  end

  def build_hexagon_sql
    user_filter = user_id ? "user_id = #{user_id}" : "1=1"
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
    return "" unless start_date || end_date

    conditions = []
    conditions << "timestamp >= EXTRACT(EPOCH FROM '#{start_date}'::timestamp)" if start_date
    conditions << "timestamp <= EXTRACT(EPOCH FROM '#{end_date}'::timestamp)" if end_date

    conditions.any? ? "AND #{conditions.join(' AND ')}" : ""
  end

  def execute_sql(sql)
    ActiveRecord::Base.connection.execute(sql)
  end

  def format_hexagons(result)
    total_points = 0

    hexagons = result.map do |row|
      point_count = row['point_count'].to_i
      total_points += point_count

      # Parse timestamps and format dates
      earliest = row['earliest_point'] ? Time.at(row['earliest_point'].to_f).iso8601 : nil
      latest = row['latest_point'] ? Time.at(row['latest_point'].to_f).iso8601 : nil

      {
        type: 'Feature',
        id: row['id'],
        geometry: JSON.parse(row['geojson']),
        properties: {
          hex_id: row['id'],
          hex_i: row['hex_i'],
          hex_j: row['hex_j'],
          hex_size: hex_size,
          point_count: point_count,
          earliest_point: earliest,
          latest_point: latest,
          density: calculate_density(point_count)
        }
      }
    end

    Rails.logger.info "Generated #{hexagons.count} hexagons containing #{total_points} points for area #{area_km2.round(2)} km²"

    {
      type: 'FeatureCollection',
      features: hexagons,
      metadata: {
        bbox: [min_lon, min_lat, max_lon, max_lat],
        area_km2: area_km2.round(2),
        hex_size_m: hex_size,
        count: hexagons.count,
        total_points: total_points,
        user_id: user_id,
        date_range: build_date_range_metadata
      }
    }
  end

  def calculate_density(point_count)
    # Calculate points per km² for the hexagon
    # A hexagon with radius 500m has area ≈ 0.65 km²
    hexagon_area_km2 = 0.65 * (hex_size / 500.0) ** 2
    (point_count / hexagon_area_km2).round(2)
  end

  def build_date_range_metadata
    return nil unless start_date || end_date

    {
      start_date: start_date,
      end_date: end_date
    }
  end

  def validate!
    return if valid?

    if area_km2 > MAX_AREA_KM2
      raise BoundingBoxTooLargeError, errors.full_messages.join(', ')
    end

    raise InvalidCoordinatesError, errors.full_messages.join(', ')
  end
end
