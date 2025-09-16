# frozen_string_literal: true

class Api::V1::Maps::HexagonsController < ApiController
  skip_before_action :authenticate_api_key, if: :public_sharing_request?
  before_action :validate_bbox_params, except: [:bounds]

  def index
    result = Maps::HexagonRequestHandler.call(
      params: params,
      current_api_user: current_api_user
    )

    render json: result
  rescue Maps::HexagonContextResolver::SharedStatsNotFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue Maps::DateParameterCoercer::InvalidDateFormatError => e
    render json: { error: e.message }, status: :bad_request
  rescue Maps::HexagonGrid::BoundingBoxTooLargeError,
         Maps::HexagonGrid::InvalidCoordinatesError => e
    render json: { error: e.message }, status: :bad_request
  rescue Maps::HexagonGrid::PostGISError => e
    render json: { error: e.message }, status: :internal_server_error
  rescue StandardError => _e
    handle_service_error
  end

  def bounds
    context = Maps::HexagonContextResolver.call(
      params: params,
      current_api_user: current_api_user
    )

    result = Maps::BoundsCalculator.call(
      target_user: context[:target_user],
      start_date: context[:start_date],
      end_date: context[:end_date]
    )

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

  def bbox_params
    params.permit(:min_lon, :min_lat, :max_lon, :max_lat, :hex_size, :viewport_width, :viewport_height)
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
