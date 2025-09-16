# frozen_string_literal: true

class Api::V1::Maps::HexagonsController < ApiController
  skip_before_action :authenticate_api_key, if: :public_sharing_request?

  def index
    result = Maps::H3HexagonRenderer.call(
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

  def hexagon_params
    params.permit(:h3_resolution, :uuid, :start_date, :end_date)
  end

  def handle_service_error
    render json: { error: 'Failed to generate hexagon grid' }, status: :internal_server_error
  end

  def public_sharing_request?
    params[:uuid].present?
  end
end
