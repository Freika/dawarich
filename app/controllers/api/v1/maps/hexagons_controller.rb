# frozen_string_literal: true

class Api::V1::Maps::HexagonsController < ApiController
  before_action :validate_bbox_params

  def index
    service = Maps::HexagonGrid.new(hexagon_params)
    result = service.call
    
    render json: result
  rescue Maps::HexagonGrid::BoundingBoxTooLargeError => e
    render json: { error: e.message }, status: :bad_request
  rescue Maps::HexagonGrid::InvalidCoordinatesError => e
    render json: { error: e.message }, status: :bad_request
  rescue Maps::HexagonGrid::PostGISError => e
    render json: { error: e.message }, status: :internal_server_error
  rescue StandardError => e
    Rails.logger.error "Hexagon generation error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: 'Failed to generate hexagon grid' }, status: :internal_server_error
  end

  private

  def bbox_params
    params.permit(:min_lon, :min_lat, :max_lon, :max_lat, :hex_size, :viewport_width, :viewport_height)
  end

  def hexagon_params
    bbox_params.merge(
      user_id: current_api_user&.id,
      start_date: params[:start_date],
      end_date: params[:end_date]
    )
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
