# frozen_string_literal: true

class Stats::CalculateMonth
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
        hexagon_data: calculate_hexagons
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

  def calculate_hexagons
    return nil if points.empty?

    # Calculate bounding box for the user's points in this month
    bounds = calculate_data_bounds
    return nil unless bounds

    # Pre-calculate hexagons for 1000m size used across the system
    hexagon_sizes = [1000] # 1000m hexagons for consistent visualization

    hexagon_sizes.each_with_object({}) do |hex_size, result|
      begin
        service = Maps::HexagonGrid.new(
          min_lon: bounds[:min_lng],
          min_lat: bounds[:min_lat],
          max_lon: bounds[:max_lng],
          max_lat: bounds[:max_lat],
          hex_size: hex_size,
          user_id: user.id,
          start_date: start_date_iso8601,
          end_date: end_date_iso8601
        )

        geojson_result = service.call

        # Store the complete GeoJSON result for instant serving
        result[hex_size.to_s] = {
          'geojson' => geojson_result,
          'bbox' => bounds,
          'generated_at' => Time.current.iso8601
        }

        Rails.logger.info "Pre-calculated #{geojson_result['features']&.size || 0} hexagons (#{hex_size}m) for user #{user.id}, #{year}-#{month}"
      rescue Maps::HexagonGrid::BoundingBoxTooLargeError,
             Maps::HexagonGrid::InvalidCoordinatesError,
             Maps::HexagonGrid::PostGISError => e
        Rails.logger.warn "Hexagon calculation failed for user #{user.id}, #{year}-#{month}, size #{hex_size}m: #{e.message}"
        # Continue with other sizes even if one fails
        next
      end
    end
  end

  def calculate_data_bounds
    bounds_result = ActiveRecord::Base.connection.exec_query(
      "SELECT MIN(ST_Y(lonlat::geometry)) as min_lat, MAX(ST_Y(lonlat::geometry)) as max_lat,
              MIN(ST_X(lonlat::geometry)) as min_lng, MAX(ST_X(lonlat::geometry)) as max_lng
       FROM points
       WHERE user_id = $1
       AND timestamp BETWEEN $2 AND $3
       AND lonlat IS NOT NULL",
      'hexagon_bounds_query',
      [user.id, start_timestamp, end_timestamp]
    ).first

    return nil unless bounds_result

    {
      min_lat: bounds_result['min_lat'].to_f,
      max_lat: bounds_result['max_lat'].to_f,
      min_lng: bounds_result['min_lng'].to_f,
      max_lng: bounds_result['max_lng'].to_f
    }
  end

  def start_date_iso8601
    DateTime.new(year, month, 1).beginning_of_day.iso8601
  end

  def end_date_iso8601
    DateTime.new(year, month, -1).end_of_day.iso8601
  end
end
