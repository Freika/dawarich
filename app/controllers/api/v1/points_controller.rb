# frozen_string_literal: true

class Api::V1::PointsController < ApiController
  before_action :authenticate_active_api_user!, only: %i[create update destroy bulk_destroy]
  before_action :validate_points_limit, only: %i[create]

  def index
    start_at = params[:start_at]&.to_datetime&.to_i
    end_at   = params[:end_at]&.to_datetime&.to_i || Time.zone.now.to_i
    order    = params[:order] || 'desc'

    points = current_api_user
             .points
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
    points = Points::Create.new(current_api_user, batch_params).call

    render json: { data: points }
  end

  def update
    point = current_api_user.points.find(params[:id])

    point.update(lonlat: "POINT(#{point_params[:longitude]} #{point_params[:latitude]})")

    render json: point_serializer.new(point).call
  end

  def destroy
    point = current_api_user.points.find(params[:id])
    point.destroy

    render json: { message: 'Point deleted successfully' }
  end

  def bulk_destroy
    point_ids = bulk_destroy_params[:point_ids]

    render json: { error: 'No points selected' }, status: :unprocessable_entity and return if point_ids.blank?

    deleted_count = current_api_user.points.where(id: point_ids).destroy_all.count

    render json: { message: 'Points were successfully destroyed', count: deleted_count }, status: :ok
  end

  private

  def point_params
    params.require(:point).permit(:latitude, :longitude)
  end

  def batch_params
    params.permit(locations: [:type, { geometry: {}, properties: {} }], batch: {})
  end

  def bulk_destroy_params
    params.permit(point_ids: [])
  end

  def point_serializer
    params[:slim] == 'true' ? Api::SlimPointSerializer : Api::PointSerializer
  end
end
