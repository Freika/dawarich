# frozen_string_literal: true

class Maps::HexagonGrid
  include ActiveModel::Validations

  # Constants for configuration
  DEFAULT_HEX_SIZE = 500 # meters (center to edge)
  MAX_AREA_KM2 = 250_000 # 500km x 500km

  # Validation error classes
  class BoundingBoxTooLargeError < StandardError; end
  class InvalidCoordinatesError < StandardError; end
  class PostGISError < StandardError; end

  attr_reader :min_lon, :min_lat, :max_lon, :max_lat, :hex_size, :user_id, :start_date, :end_date, :viewport_width,
              :viewport_height

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
    @viewport_width = params[:viewport_width]&.to_f
    @viewport_height = params[:viewport_height]&.to_f
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

  private

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

  def validate_bbox_order
    errors.add(:base, 'min_lon must be less than max_lon') if min_lon >= max_lon
    errors.add(:base, 'min_lat must be less than max_lat') if min_lat >= max_lat
  end

  def validate_area_size
    return unless area_km2 > MAX_AREA_KM2

    errors.add(:base, "Area too large (#{area_km2.round} km²). Maximum allowed: #{MAX_AREA_KM2} km²")
  end

  def generate_hexagons
    query = HexagonQuery.new(
      min_lon:, min_lat:, max_lon:, max_lat:,
      hex_size:, user_id:, start_date:, end_date:
    )

    result = query.call

    format_hexagons(result)
  rescue ActiveRecord::StatementInvalid => e
    message = "Failed to generate hexagon grid: #{e.message}"

    ExceptionReporter.call(e, message)
    raise PostGISError, message
  end

  def format_hexagons(result)
    total_points = 0

    hexagons = result.map do |row|
      point_count = row['point_count'].to_i
      total_points += point_count

      # Parse timestamps and format dates
      earliest = row['earliest_point'] ? Time.zone.at(row['earliest_point'].to_f).iso8601 : nil
      latest = row['latest_point'] ? Time.zone.at(row['latest_point'].to_f).iso8601 : nil

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
          latest_point: latest
        }
      }
    end

    {
      'type' => 'FeatureCollection',
      'features' => hexagons,
      'metadata' => {
        'bbox' => [min_lon, min_lat, max_lon, max_lat],
        'area_km2' => area_km2.round(2),
        'hex_size_m' => hex_size,
        'count' => hexagons.count,
        'total_points' => total_points,
        'user_id' => user_id,
        'date_range' => build_date_range_metadata
      }
    }
  end

  def build_date_range_metadata
    return nil unless start_date || end_date

    { 'start_date' => start_date, 'end_date' => end_date }
  end

  def validate!
    return if valid?

    raise BoundingBoxTooLargeError, errors.full_messages.join(', ') if area_km2 > MAX_AREA_KM2

    raise InvalidCoordinatesError, errors.full_messages.join(', ')
  end

  def viewport_valid?
    viewport_width &&
      viewport_height &&
      viewport_width.positive? &&
      viewport_height.positive?
  end
end
