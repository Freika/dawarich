# frozen_string_literal: true

class Api::V1::PointsController < ApiController
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

  def destroy
    point = current_api_user.tracked_points.find(params[:id])
    point.destroy

    render json: { message: 'Point deleted successfully' }
  end

  private

  def point_serializer
    params[:slim] == 'true' ? SlimPointSerializer : PointSerializer
  end
end
