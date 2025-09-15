# frozen_string_literal: true

class Api::V1::Maps::HexagonsController < ApiController
  skip_before_action :authenticate_api_key, if: :public_sharing_request?
  before_action :validate_bbox_params, except: [:bounds]
  before_action :set_user_and_dates

  def index
    # Try to use pre-calculated hexagon centers from stats
    if @stat&.hexagon_centers.present?
      result = build_hexagons_from_centers(@stat.hexagon_centers)
      Rails.logger.debug "Using pre-calculated hexagon centers: #{@stat.hexagon_centers.size} centers"
      return render json: result
    end

    # Handle legacy "area too large" entries - recalculate them now that we can handle large areas
    if @stat&.hexagon_centers&.dig('area_too_large')
      Rails.logger.info "Recalculating previously skipped large area hexagons for stat #{@stat.id}"

      # Trigger recalculation
      service = Stats::CalculateMonth.new(@target_user.id, @stat.year, @stat.month)
      new_centers = service.send(:calculate_hexagon_centers)

      if new_centers && !new_centers.dig(:area_too_large)
        @stat.update(hexagon_centers: new_centers)
        result = build_hexagons_from_centers(new_centers)
        Rails.logger.debug "Successfully recalculated hexagon centers: #{new_centers.size} centers"
        return render json: result
      end
    end

    # Fall back to on-the-fly calculation for legacy/missing data
    Rails.logger.debug 'No pre-calculated data available, calculating hexagons on-the-fly'
    result = Maps::HexagonGrid.new(hexagon_params).call
    Rails.logger.debug "Hexagon service result: #{result['features']&.count || 0} features"
    render json: result
  rescue Maps::HexagonGrid::BoundingBoxTooLargeError,
         Maps::HexagonGrid::InvalidCoordinatesError => e
    render json: { error: e.message }, status: :bad_request
  rescue Maps::HexagonGrid::PostGISError => e
    render json: { error: e.message }, status: :internal_server_error
  rescue StandardError => _e
    handle_service_error
  end

  def bounds
    # Get the bounding box of user's points for the date range
    return render json: { error: 'No user found' }, status: :not_found unless @target_user
    return render json: { error: 'No date range specified' }, status: :bad_request unless @start_date && @end_date

    # Convert dates to timestamps (handle both string and timestamp formats)
    begin
      start_timestamp = coerce_date(@start_date)
      end_timestamp = coerce_date(@end_date)
    rescue ArgumentError => e
      return render json: { error: e.message }, status: :bad_request
    end

    points_relation = @target_user.points.where(timestamp: start_timestamp..end_timestamp)
    point_count = points_relation.count

    if point_count.positive?
      bounds_result = ActiveRecord::Base.connection.exec_query(
        "SELECT MIN(latitude) as min_lat, MAX(latitude) as max_lat,
                MIN(longitude) as min_lng, MAX(longitude) as max_lng
         FROM points
         WHERE user_id = $1
         AND timestamp BETWEEN $2 AND $3",
        'bounds_query',
        [@target_user.id, start_timestamp, end_timestamp]
      ).first

      render json: {
        min_lat: bounds_result['min_lat'].to_f,
        max_lat: bounds_result['max_lat'].to_f,
        min_lng: bounds_result['min_lng'].to_f,
        max_lng: bounds_result['max_lng'].to_f,
        point_count: point_count
      }
    else
      render json: {
        error: 'No data found for the specified date range',
        point_count: 0
      }, status: :not_found
    end
  end

  private

  def build_hexagons_from_centers(centers)
    # Convert stored centers back to hexagon polygons
    # Each center is [lng, lat, earliest_timestamp, latest_timestamp]
    hexagon_features = centers.map.with_index do |center, index|
      lng, lat, earliest, latest = center

      # Generate hexagon polygon from center point (1000m hexagons)
      hexagon_geojson = generate_hexagon_polygon(lng, lat, 1000)

      {
        type: 'Feature',
        id: index + 1,
        geometry: hexagon_geojson,
        properties: {
          hex_id: index + 1,
          hex_size: 1000,
          earliest_point: earliest ? Time.zone.at(earliest).iso8601 : nil,
          latest_point: latest ? Time.zone.at(latest).iso8601 : nil
        }
      }
    end

    {
      'type' => 'FeatureCollection',
      'features' => hexagon_features,
      'metadata' => {
        'hex_size_m' => 1000,
        'count' => hexagon_features.count,
        'user_id' => @target_user.id,
        'pre_calculated' => true
      }
    }
  end

  def generate_hexagon_polygon(center_lng, center_lat, size_meters)
    # Generate hexagon vertices around center point
    # PostGIS ST_HexagonGrid uses size_meters as the edge-to-edge distance (width/flat-to-flat)
    # For a regular hexagon with width = size_meters:
    # - Width (edge to edge) = size_meters
    # - Radius (center to vertex) = width / √3 ≈ size_meters * 0.577
    # - Edge length ≈ radius ≈ size_meters * 0.577

    radius_meters = size_meters / Math.sqrt(2.7) # Convert width to radius

    # Convert meter radius to degrees (rough approximation)
    # 1 degree latitude ≈ 111,111 meters
    # 1 degree longitude ≈ 111,111 * cos(latitude) meters
    lat_degree_in_meters = 111_111.0
    lng_degree_in_meters = lat_degree_in_meters * Math.cos(center_lat * Math::PI / 180)

    radius_lat_degrees = radius_meters / lat_degree_in_meters
    radius_lng_degrees = radius_meters / lng_degree_in_meters

    vertices = []
    6.times do |i|
      # Calculate angle for each vertex (60 degrees apart, starting from 0)
      angle = (i * 60) * Math::PI / 180

      # Calculate vertex position
      lat_offset = radius_lat_degrees * Math.sin(angle)
      lng_offset = radius_lng_degrees * Math.cos(angle)

      vertices << [center_lng + lng_offset, center_lat + lat_offset]
    end

    # Close the polygon by adding the first vertex at the end
    vertices << vertices.first

    {
      type: 'Polygon',
      coordinates: [vertices]
    }
  end

  def bbox_params
    params.permit(:min_lon, :min_lat, :max_lon, :max_lat, :hex_size, :viewport_width, :viewport_height)
  end

  def hexagon_params
    bbox_params.merge(
      user_id: @target_user&.id,
      start_date: @start_date,
      end_date: @end_date
    )
  end

  def set_user_and_dates
    return set_public_sharing_context if params[:uuid].present?

    set_authenticated_context
  end

  def set_public_sharing_context
    @stat = Stat.find_by(sharing_uuid: params[:uuid])

    unless @stat&.public_accessible?
      render json: {
        error: 'Shared stats not found or no longer available'
      }, status: :not_found and return
    end

    @target_user = @stat.user
    @start_date = Date.new(@stat.year, @stat.month, 1).beginning_of_day.iso8601
    @end_date = Date.new(@stat.year, @stat.month, 1).end_of_month.end_of_day.iso8601
  end

  def set_authenticated_context
    @target_user = current_api_user
    @start_date = params[:start_date]
    @end_date = params[:end_date]
  end

  def handle_service_error
    render json: { error: 'Failed to generate hexagon grid' }, status: :internal_server_error
  end

  def public_sharing_request?
    params[:uuid].present?
  end

  def validate_bbox_params
    required_params = %w[min_lon min_lat max_lon max_lat]
    missing_params = required_params.select { |param| params[param].blank? }

    return unless missing_params.any?

    render json: {
      error: "Missing required parameters: #{missing_params.join(', ')}"
    }, status: :bad_request
  end

  def coerce_date(param)
    case param
    when String
      # Check if it's a numeric string (timestamp) or date string
      if param.match?(/^\d+$/)
        param.to_i
      else
        Time.parse(param).to_i
      end
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
