# frozen_string_literal: true

class Api::V1::PointsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[create update destroy]

  def index
    start_at = params[:start_at]&.to_datetime&.to_i
    end_at   = params[:end_at]&.to_datetime&.to_i || Time.zone.now.to_i
    order    = params[:order] || 'desc'

    points = current_api_user
             .tracked_points
             .where(timestamp: start_at..end_at)
             .order(timestamp: order)
             .page(params[:page])
             .per(params[:per_page] || 100)

    serialized_points = points.map { |point| point_serializer.new(point).call }

    response.set_header('X-Current-Page', points.current_page.to_s)
    response.set_header('X-Total-Pages', points.total_pages.to_s)

    render json: serialized_points
  end

  def create
    Points::CreateJob.perform_later(batch_params, current_api_user.id)

    render json: { message: 'Points are being processed' }
  end

  def update
    point = current_api_user.tracked_points.find(params[:id])

    point.update(point_params)

    render json: point_serializer.new(point).call
  end

  def destroy
    point = current_api_user.tracked_points.find(params[:id])
    point.destroy

    render json: { message: 'Point deleted successfully' }
  end

  private

  def point_params
    params.require(:point).permit(:latitude, :longitude)
  end

  def batch_params
    params.permit(locations: [:type, { geometry: {}, properties: {} }], batch: {})
  end

  def point_serializer
    params[:slim] == 'true' ? Api::SlimPointSerializer : Api::PointSerializer
  end
end
