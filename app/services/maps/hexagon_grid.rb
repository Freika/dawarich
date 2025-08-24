# frozen_string_literal: true

class Maps::HexagonGrid
  include ActiveModel::Validations
  
  # Constants for configuration
  DEFAULT_HEX_SIZE = 500 # meters (center to edge)
  MAX_HEXAGONS_PER_REQUEST = 5000
  MAX_AREA_KM2 = 250_000 # 500km x 500km
  
  # Validation error classes
  class BoundingBoxTooLargeError < StandardError; end
  class InvalidCoordinatesError < StandardError; end
  class PostGISError < StandardError; end

  attr_reader :min_lon, :min_lat, :max_lon, :max_lat, :hex_size

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
    @hex_size = params[:hex_size]&.to_f || DEFAULT_HEX_SIZE
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
      hex_grid AS (
        SELECT 
          (ST_HexagonGrid(#{hex_size}, bbox_utm.geom_utm)).geom as hex_geom_utm,
          (ST_HexagonGrid(#{hex_size}, bbox_utm.geom_utm)).i as hex_i,
          (ST_HexagonGrid(#{hex_size}, bbox_utm.geom_utm)).j as hex_j
        FROM bbox_utm
      )
      SELECT 
        ST_AsGeoJSON(ST_Transform(hex_geom_utm, 4326)) as geojson,
        hex_i,
        hex_j,
        row_number() OVER (ORDER BY hex_i, hex_j) as id
      FROM hex_grid
      WHERE ST_Intersects(
        hex_geom_utm,
        (SELECT geom_utm FROM bbox_utm)
      )
      LIMIT #{MAX_HEXAGONS_PER_REQUEST};
    SQL
  end

  def execute_sql(sql)
    ActiveRecord::Base.connection.execute(sql)
  end

  def format_hexagons(result)
    hexagons = result.map do |row|
      {
        type: 'Feature',
        id: row['id'],
        geometry: JSON.parse(row['geojson']),
        properties: {
          hex_id: row['id'],
          hex_i: row['hex_i'],
          hex_j: row['hex_j'],
          hex_size: hex_size
        }
      }
    end

    Rails.logger.info "Generated #{hexagons.count} hexagons for area #{area_km2.round(2)} km²"
    
    {
      type: 'FeatureCollection',
      features: hexagons,
      metadata: {
        bbox: [min_lon, min_lat, max_lon, max_lat],
        area_km2: area_km2.round(2),
        hex_size_m: hex_size,
        count: hexagons.count,
        estimated_count: estimated_hexagon_count
      }
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