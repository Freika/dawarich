# frozen_string_literal: true

class Stats::HexagonCalculator
  # H3 Configuration
  DEFAULT_H3_RESOLUTION = 8 # Small hexagons for good detail
  MAX_HEXAGONS = 10_000 # Maximum number of hexagons to prevent memory issues

  class PostGISError < StandardError; end

  def initialize(user_id, year, month)
    @user = User.find(user_id)
    @year = year.to_i
    @month = month.to_i
  end

  def call(h3_resolution: DEFAULT_H3_RESOLUTION)
    calculate_h3_hexagon_centers(h3_resolution)
  end

  private

  attr_reader :user, :year, :month

  def calculate_h3_hexagon_centers(h3_resolution)
    result = calculate_hexagons(h3_resolution)
    return [] if result.nil?

    # Convert to array format: [h3_index_string, point_count, earliest_timestamp, latest_timestamp]
    result.map do |h3_index_string, data|
      [
        h3_index_string,
        data[0], # count
        data[1], # earliest
        data[2]  # latest
      ]
    end
  end

  # Unified hexagon calculation method
  def calculate_hexagons(h3_resolution)
    return nil if points.empty?

    begin
      h3_hash = calculate_h3_indexes(points, h3_resolution)

      if h3_hash.empty?
        Rails.logger.info "No H3 hex IDs calculated for user #{user.id}, #{year}-#{month} (no data)"
        return nil
      end

      if h3_hash.size > MAX_HEXAGONS
        Rails.logger.warn "Too many hexagons (#{h3_hash.size}), using lower resolution"
        # Try with lower resolution (larger hexagons)
        lower_resolution = [h3_resolution - 2, 0].max
        Rails.logger.info "Recalculating with lower H3 resolution: #{lower_resolution}"
        # Create a new instance with lower resolution for recursion
        return self.class.new(user.id, year, month).calculate_hexagons(lower_resolution)
      end

      Rails.logger.info "Generated #{h3_hash.size} H3 hexagons at resolution #{h3_resolution} for user #{user.id}"
      h3_hash
    rescue StandardError => e
      message = "Failed to calculate H3 hexagon centers: #{e.message}"
      ExceptionReporter.call(e, message) if defined?(ExceptionReporter)
      raise PostGISError, message
    end
  end

  def start_timestamp
    DateTime.new(year, month, 1).to_i
  end

  def end_timestamp
    DateTime.new(year, month, -1).to_i # -1 returns last day of month
  end

  def points
    return @points if defined?(@points)

    @points = user
              .points
              .without_raw_data
              .where(timestamp: start_timestamp..end_timestamp)
              .where.not(lonlat: nil)
              .select(:lonlat, :timestamp)
              .order(timestamp: :asc)
  end

  def calculate_h3_indexes(points, h3_resolution)
    h3_data = {}

    points.find_each do |point|
      # Extract lat/lng from PostGIS point
      coordinates = [point.lonlat.y, point.lonlat.x] # [lat, lng] for H3

      # Get H3 index for this point
      h3_index = H3.from_geo_coordinates(coordinates, h3_resolution.clamp(0, 15))
      h3_index_string = h3_index.to_s(16) # Convert to hex string immediately

      # Initialize or update data for this hexagon
      if h3_data[h3_index_string]
        data = h3_data[h3_index_string]
        data[0] += 1 # increment count
        data[1] = [data[1], point.timestamp].min # update earliest
        data[2] = [data[2], point.timestamp].max # update latest
      else
        h3_data[h3_index_string] = [1, point.timestamp, point.timestamp] # [count, earliest, latest]
      end
    end

    h3_data
  end
end
