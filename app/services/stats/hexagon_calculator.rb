# frozen_string_literal: true

class Stats::HexagonCalculator
  # H3 Configuration
  DEFAULT_H3_RESOLUTION = 8 # Small hexagons for good detail
  MAX_HEXAGONS = 10_000 # Maximum number of hexagons to prevent memory issues
  BATCH_SIZE = 50_000

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
    h3_hash = build_h3_hash(h3_resolution)

    if h3_hash.empty?
      Rails.logger.info "No H3 hex IDs calculated for user #{user.id}, #{year}-#{month} (no data)"
      return nil
    end

    if h3_hash.size > MAX_HEXAGONS
      Rails.logger.warn "Too many hexagons (#{h3_hash.size}), using lower resolution"
      # Try with lower resolution (larger hexagons)
      lower_resolution = [h3_resolution - 2, 0].max
      Rails.logger.info "Recalculating with lower H3 resolution: #{lower_resolution}"
      return calculate_hexagons(lower_resolution)
    end

    Rails.logger.info "Generated #{h3_hash.size} H3 hexagons at resolution #{h3_resolution} for user #{user.id}"
    h3_hash
  rescue StandardError => e
    message = "Failed to calculate H3 hexagon centers: #{e.message}"
    ExceptionReporter.call(e, message) if defined?(ExceptionReporter)
    raise PostGISError, message
  end

  def start_timestamp
    (DateTime.new(year, month, 1) - 2.days).to_i
  end

  def end_timestamp
    (DateTime.new(year, month, -1, 23, 59, 59) + 2.days).to_i
  end

  def points
    return @points if defined?(@points)

    tz = user.timezone_iana
    @points = user
              .points
              .not_anomaly
              .without_raw_data
              .where(timestamp: start_timestamp..end_timestamp)
              .where.not(lonlat: nil)
              .where(
                'EXTRACT(year FROM (to_timestamp(timestamp) AT TIME ZONE ?)) = ? ' \
                'AND EXTRACT(month FROM (to_timestamp(timestamp) AT TIME ZONE ?)) = ?',
                tz, year, tz, month
              )
              .select(:lonlat, :timestamp)
              .order(timestamp: :asc)
  end

  def build_h3_hash(h3_resolution)
    resolution = h3_resolution.clamp(0, 15)
    h3_data = {}

    each_coordinate_batch do |rows|
      rows.each do |_id, lat, lng, timestamp|
        h3_index_string = H3.from_geo_coordinates([lat, lng], resolution).to_s(16)
        if (data = h3_data[h3_index_string])
          data[0] += 1
          data[1] = [data[1], timestamp].min
          data[2] = [data[2], timestamp].max
        else
          h3_data[h3_index_string] = [1, timestamp, timestamp]
        end
      end
    end

    h3_data
  end

  def each_coordinate_batch
    relation = points.unscope(:select, :order).reorder(:id)
    last_id = 0

    loop do
      rows = relation.where('points.id > ?', last_id).limit(BATCH_SIZE).pluck(
        :id, Arel.sql('ST_Y(lonlat::geometry)'), Arel.sql('ST_X(lonlat::geometry)'), :timestamp
      )
      break if rows.empty?

      last_id = rows.last.first
      yield rows
      break if rows.size < BATCH_SIZE
    end
  end
end
