# frozen_string_literal: true

class Maps::H3HexagonCenters
  include ActiveModel::Validations

  # H3 Configuration
  DEFAULT_H3_RESOLUTION = 8 # Small hexagons for good detail
  MAX_HEXAGONS = 10_000 # Maximum number of hexagons to prevent memory issues

  class PostGISError < StandardError; end

  attr_reader :user_id, :start_date, :end_date, :h3_resolution

  def initialize(user_id:, start_date:, end_date:, h3_resolution: DEFAULT_H3_RESOLUTION)
    @user_id = user_id
    @start_date = start_date
    @end_date = end_date
    @h3_resolution = h3_resolution.clamp(0, 15) # Ensure valid H3 resolution
  end

  def call
    points = fetch_user_points
    return [] if points.empty?

    h3_indexes_with_counts = calculate_h3_indexes(points)

    if h3_indexes_with_counts.size > MAX_HEXAGONS
      Rails.logger.warn "Too many hexagons (#{h3_indexes_with_counts.size}), using lower resolution"
      # Try with lower resolution (larger hexagons)
      return recalculate_with_lower_resolution
    end

    Rails.logger.info "Generated #{h3_indexes_with_counts.size} H3 hexagons at resolution #{h3_resolution} for user #{user_id}"

    # Convert to format: [h3_index_string, point_count, earliest_timestamp, latest_timestamp]
    h3_indexes_with_counts.map do |h3_index, data|
      [
        h3_index.to_s(16), # Store as hex string
        data[:count],
        data[:earliest],
        data[:latest]
      ]
    end
  rescue StandardError => e
    message = "Failed to calculate H3 hexagon centers: #{e.message}"
    ExceptionReporter.call(e, message)
    raise PostGISError, message
  end

  private

  def fetch_user_points
    start_timestamp = Maps::DateParameterCoercer.new(start_date).call
    end_timestamp = Maps::DateParameterCoercer.new(end_date).call

    Point.where(user_id: user_id)
         .where(timestamp: start_timestamp..end_timestamp)
         .where.not(lonlat: nil)
         .select(:id, :lonlat, :timestamp)
  rescue Maps::DateParameterCoercer::InvalidDateFormatError => e
    ExceptionReporter.call(e, e.message) if defined?(ExceptionReporter)
    raise ArgumentError, e.message
  end

  def calculate_h3_indexes(points)
    h3_data = Hash.new { |h, k| h[k] = { count: 0, earliest: nil, latest: nil } }

    points.find_each do |point|
      # Extract lat/lng from PostGIS point
      coordinates = [point.lonlat.y, point.lonlat.x] # [lat, lng] for H3

      # Get H3 index for this point
      h3_index = H3.from_geo_coordinates(coordinates, h3_resolution)

      # Aggregate data for this hexagon
      data = h3_data[h3_index]
      data[:count] += 1
      data[:earliest] = [data[:earliest], point.timestamp].compact.min
      data[:latest] = [data[:latest], point.timestamp].compact.max
    end

    h3_data
  end

  def recalculate_with_lower_resolution
    # Try with resolution 2 levels lower (4x larger hexagons)
    lower_resolution = [h3_resolution - 2, 0].max

    Rails.logger.info "Recalculating with lower H3 resolution: #{lower_resolution}"

    service = self.class.new(
      user_id: user_id,
      start_date: start_date,
      end_date: end_date,
      h3_resolution: lower_resolution
    )

    service.call
  end
end
