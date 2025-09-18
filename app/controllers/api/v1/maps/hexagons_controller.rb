# frozen_string_literal: true

class Api::V1::Maps::HexagonsController < ApiController
  skip_before_action :authenticate_api_key, if: :public_sharing_request?

  def index
    return unless public_sharing_request? || validate_required_parameters

    result = Maps::HexagonRequestHandler.call(
      params: params,
      current_api_user: current_api_user
    )

    render json: result
  rescue Maps::HexagonContextResolver::SharedStatsNotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue Maps::DateParameterCoercer::InvalidDateFormatError => e
    render json: { error: e.message }, status: :bad_request
  rescue Maps::H3HexagonCenters::TooManyHexagonsError,
         Maps::H3HexagonCenters::InvalidCoordinatesError,
         Maps::H3HexagonCenters::PostGISError => e
    render json: { error: e.message }, status: :bad_request
  rescue StandardError => _e
    handle_service_error
  end

  def bounds
    context = Maps::HexagonContextResolver.call(
      params: params,
      current_api_user: current_api_user
    )

    result = Maps::BoundsCalculator.new(
      target_user: context[:target_user],
      start_date: context[:start_date],
      end_date: context[:end_date]
    ).call

    if result[:success]
      render json: result[:data]
    else
      render json: {
        error: result[:error],
        point_count: result[:point_count]
      }, status: :not_found
    end
  rescue Maps::HexagonContextResolver::SharedStatsNotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue Maps::BoundsCalculator::NoUserFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue Maps::BoundsCalculator::NoDateRangeError => e
    render json: { error: e.message }, status: :bad_request
  rescue Maps::DateParameterCoercer::InvalidDateFormatError => e
    render json: { error: e.message }, status: :bad_request
  end

  private

  def hexagon_params
    params.permit(:h3_resolution, :uuid, :start_date, :end_date)
  end

  def handle_service_error
    render json: { error: 'Failed to generate hexagon grid' }, status: :internal_server_error
  end

  def public_sharing_request?
    params[:uuid].present?
  end

  def validate_required_parameters
    required_params = %i[min_lon max_lon min_lat max_lat start_date end_date]
    missing_params = required_params.select { |param| params[param].blank? }

    unless missing_params.empty?
      error_message = "Missing required parameters: #{missing_params.join(', ')}"
      render json: { error: error_message }, status: :bad_request
      return false
    end

    # Validate coordinate ranges
    if !valid_coordinate_ranges?
      render json: { error: 'Invalid coordinate ranges' }, status: :bad_request
      return false
    end

    true
  end

  def valid_coordinate_ranges?
    min_lon = params[:min_lon].to_f
    max_lon = params[:max_lon].to_f
    min_lat = params[:min_lat].to_f
    max_lat = params[:max_lat].to_f

    # Check longitude range (-180 to 180)
    return false unless (-180..180).cover?(min_lon) && (-180..180).cover?(max_lon)
    # Check latitude range (-90 to 90)
    return false unless (-90..90).cover?(min_lat) && (-90..90).cover?(max_lat)
    # Check that min values are less than max values
    return false unless min_lon < max_lon && min_lat < max_lat

    true
  end
end
