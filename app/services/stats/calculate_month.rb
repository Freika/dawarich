# frozen_string_literal: true

class Stats::CalculateMonth
  include ActiveModel::Validations

  # H3 Configuration
  DEFAULT_H3_RESOLUTION = 8 # Small hexagons for good detail
  MAX_HEXAGONS = 10_000 # Maximum number of hexagons to prevent memory issues

  class PostGISError < StandardError; end

  def initialize(user_id, year, month)
    @user = User.find(user_id)
    @year = year.to_i
    @month = month.to_i
  end

  def call
    if points.empty?
      destroy_month_stats(year, month)

      return
    end

    update_month_stats(year, month)
  rescue StandardError => e
    create_stats_update_failed_notification(user, e)
  end

  # Public method for calculating H3 hexagon centers with custom parameters
  def calculate_h3_hexagon_centers(user_id: nil, start_date: nil, end_date: nil, h3_resolution: DEFAULT_H3_RESOLUTION)
    target_start_date = start_date || start_date_iso8601
    target_end_date = end_date || end_date_iso8601

    points = fetch_user_points_for_period(user_id, target_start_date, target_end_date)
    return [] if points.empty?

    h3_indexes_with_counts = calculate_h3_indexes(points, h3_resolution)

    if h3_indexes_with_counts.size > MAX_HEXAGONS
      Rails.logger.warn "Too many hexagons (#{h3_indexes_with_counts.size}), using lower resolution"
      # Try with lower resolution (larger hexagons)
      lower_resolution = [h3_resolution - 2, 0].max
      Rails.logger.info "Recalculating with lower H3 resolution: #{lower_resolution}"
      return calculate_h3_hexagon_centers(
        user_id: user_id,
        start_date: target_start_date,
        end_date: target_end_date,
        h3_resolution: lower_resolution
      )
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
    ExceptionReporter.call(e, message) if defined?(ExceptionReporter)
    raise PostGISError, message
  end

  private

  attr_reader :user, :year, :month

  def start_timestamp = DateTime.new(year, month, 1).to_i

  def end_timestamp
    DateTime.new(year, month, -1).to_i # -1 returns last day of month
  end

  def update_month_stats(year, month)
    Stat.transaction do
      stat = Stat.find_or_initialize_by(year:, month:, user:)
      distance_by_day = stat.distance_by_day

      stat.assign_attributes(
        daily_distance: distance_by_day,
        distance: distance(distance_by_day),
        toponyms: toponyms,
        h3_hex_ids: calculate_h3_hex_ids
      )
      stat.save
    end
  end

  def points
    return @points if defined?(@points)

    @points = user
              .points
              .without_raw_data
              .where(timestamp: start_timestamp..end_timestamp)
              .select(:lonlat, :timestamp)
              .order(timestamp: :asc)
  end

  def distance(distance_by_day)
    distance_by_day.sum { |day| day[1] }
  end

  def toponyms
    toponym_points =
      user
      .points
      .without_raw_data
      .where(timestamp: start_timestamp..end_timestamp)
      .select(:city, :country_name)
      .distinct

    CountriesAndCities.new(toponym_points).call
  end

  def create_stats_update_failed_notification(user, error)
    Notifications::Create.new(
      user:,
      kind: :error,
      title: 'Stats update failed',
      content: "#{error.message}, stacktrace: #{error.backtrace.join("\n")}"
    ).call
  end

  def destroy_month_stats(year, month)
    Stat.where(year:, month:, user:).destroy_all
  end

  def calculate_h3_hex_ids
    return {} if points.empty?

    begin
      result = calculate_h3_hexagon_centers

      if result.empty?
        Rails.logger.info "No H3 hex IDs calculated for user #{user.id}, #{year}-#{month} (no data)"
        return {}
      end

      # Convert array format to hash format: { h3_index => [count, earliest, latest] }
      hex_hash = result.each_with_object({}) do |hex_data, hash|
        h3_index, count, earliest, latest = hex_data
        hash[h3_index] = [count, earliest, latest]
      end

      Rails.logger.info "Pre-calculated #{hex_hash.size} H3 hex IDs for user #{user.id}, #{year}-#{month}"
      hex_hash
    rescue PostGISError => e
      Rails.logger.warn "H3 hex IDs calculation failed for user #{user.id}, #{year}-#{month}: #{e.message}"
      {}
    end
  end

  def start_date_iso8601
    DateTime.new(year, month, 1).beginning_of_day.iso8601
  end

  def end_date_iso8601
    DateTime.new(year, month, -1).end_of_day.iso8601
  end

  def fetch_user_points_for_period(user_id, start_date, end_date)
    start_timestamp = parse_date_parameter(start_date)
    end_timestamp = parse_date_parameter(end_date)

    Point.where(user_id: user_id)
         .where(timestamp: start_timestamp..end_timestamp)
         .where.not(lonlat: nil)
         .select(:id, :lonlat, :timestamp)
  end

  def calculate_h3_indexes(points, h3_resolution)
    h3_data = Hash.new { |h, k| h[k] = { count: 0, earliest: nil, latest: nil } }

    points.find_each do |point|
      # Extract lat/lng from PostGIS point
      coordinates = [point.lonlat.y, point.lonlat.x] # [lat, lng] for H3

      # Get H3 index for this point
      h3_index = H3.from_geo_coordinates(coordinates, h3_resolution.clamp(0, 15))

      # Aggregate data for this hexagon
      data = h3_data[h3_index]
      data[:count] += 1
      data[:earliest] = [data[:earliest], point.timestamp].compact.min
      data[:latest] = [data[:latest], point.timestamp].compact.max
    end

    h3_data
  end

  def parse_date_parameter(param)
    case param
    when String
      param.match?(/^\d+$/) ? param.to_i : Time.zone.parse(param).to_i
    when Integer
      param
    else
      param.to_i
    end
  rescue ArgumentError => e
    Rails.logger.error "Invalid date format: #{param} - #{e.message}"
    raise ArgumentError, "Invalid date format: #{param}"
  end
end
