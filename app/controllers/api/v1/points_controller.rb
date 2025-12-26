# frozen_string_literal: true

class Api::V1::PointsController < ApiController
  include SafeTimestampParser

  before_action :authenticate_active_api_user!, only: %i[create update destroy bulk_destroy]
  before_action :validate_points_limit, only: %i[create]

  def index
    start_at = params[:start_at].present? ? safe_timestamp(params[:start_at]) : nil
    end_at   = params[:end_at].present? ? safe_timestamp(params[:end_at]) : Time.zone.now.to_i
    order    = params[:order] || 'desc'

    points = current_api_user
             .points
             .where(timestamp: start_at..end_at)

    # Filter by geographic bounds if provided
    if params[:min_longitude].present? && params[:max_longitude].present? &&
       params[:min_latitude].present? && params[:max_latitude].present?
      min_lng = params[:min_longitude].to_f
      max_lng = params[:max_longitude].to_f
      min_lat = params[:min_latitude].to_f
      max_lat = params[:max_latitude].to_f

      # Use PostGIS to filter points within bounding box
      points = points.where(
        'ST_X(lonlat::geometry) BETWEEN ? AND ? AND ST_Y(lonlat::geometry) BETWEEN ? AND ?',
        min_lng, max_lng, min_lat, max_lat
      )
    end

    points = points
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
