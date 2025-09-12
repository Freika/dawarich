# frozen_string_literal: true

class Api::V1::Maps::HexagonsController < ApiController
  skip_before_action :authenticate_api_key, if: :public_sharing_request?
  before_action :validate_bbox_params, except: [:bounds]
  before_action :set_user_and_dates

  def index
    service = Maps::HexagonGrid.new(hexagon_params)
    result = service.call

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

    points_relation = @target_user.points.where(timestamp: @start_date..@end_date)
    point_count = points_relation.count

    if point_count.positive?
      bounds_result = ActiveRecord::Base.connection.exec_query(
        "SELECT MIN(latitude) as min_lat, MAX(latitude) as max_lat,
                MIN(longitude) as min_lng, MAX(longitude) as max_lng
         FROM points
         WHERE user_id = $1
         AND timestamp BETWEEN $2 AND $3",
        'bounds_query',
        [@target_user.id, @start_date.to_i, @end_date.to_i]
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
    if params[:uuid].present?
      set_public_sharing_context
    else
      set_authenticated_context
    end
  end

  def set_public_sharing_context
    @stat = Stat.find_by(sharing_uuid: params[:uuid])

    unless @stat&.public_accessible?
      render json: {
        error: 'Shared stats not found or no longer available'
      }, status: :not_found and return
    end

    @target_user = @stat.user
    @start_date = Date.new(@stat.year, @stat.month, 1).beginning_of_day
    @end_date = @start_date.end_of_month.end_of_day
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
end
