# frozen_string_literal: true

class Api::V1::Maps::HexagonsController < ApiController
  skip_before_action :authenticate_api_key, if: :public_sharing_request?

  def index
    context = resolve_hexagon_context

    result = Maps::HexagonRequestHandler.new(
      params: params,
      user: current_api_user,
      context: context
    ).call

    render json: result
  rescue ActionController::ParameterMissing => e
    render json: { error: "Missing required parameter: #{e.param}" }, status: :bad_request
  rescue ActionController::BadRequest => e
    render json: { error: e.message }, status: :bad_request
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: 'Shared stats not found or no longer available' }, status: :not_found
  rescue Stats::CalculateMonth::PostGISError => e
    render json: { error: e.message }, status: :bad_request
  rescue StandardError => _e
    handle_service_error
  end

  def bounds
    context = resolve_hexagon_context

    result = Maps::BoundsCalculator.new(
      user: context[:user] || context[:target_user],
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
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: 'Shared stats not found or no longer available' }, status: :not_found
  rescue ArgumentError => e
    render json: { error: e.message }, status: :bad_request
  rescue Maps::BoundsCalculator::NoUserFoundError => e
    render json: { error: e.message }, status: :not_found
  rescue Maps::BoundsCalculator::NoDateRangeError => e
    render json: { error: e.message }, status: :bad_request
  end

  private

  def resolve_hexagon_context
    return resolve_public_sharing_context if public_sharing_request?

    resolve_authenticated_context
  end

  def resolve_public_sharing_context
    stat = Stat.find_by(sharing_uuid: params[:uuid])
    raise ActiveRecord::RecordNotFound unless stat&.public_accessible?

    {
      user: stat.user,
      start_date: Date.new(stat.year, stat.month, 1).beginning_of_day.iso8601,
      end_date: Date.new(stat.year, stat.month, 1).end_of_month.end_of_day.iso8601,
      stat: stat
    }
  end

  def resolve_authenticated_context
    {
      user: current_api_user,
      start_date: params[:start_date],
      end_date: params[:end_date],
      stat: nil
    }
  end

  def handle_service_error
    render json: { error: 'Failed to generate hexagon grid' }, status: :internal_server_error
  end

  def public_sharing_request?
    params[:uuid].present?
  end
end
