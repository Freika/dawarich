# frozen_string_literal: true

class Api::V1::PointsController < ApiController
  def index
    start_at = params[:start_at]&.to_datetime&.to_i
    end_at = params[:end_at]&.to_datetime&.to_i || Time.zone.now.to_i

    points = current_api_user
             .tracked_points
             .where(timestamp: start_at..end_at)
             .order(:timestamp)
             .page(params[:page])
             .per(params[:per_page] || 100)

    response.set_header('X-Current-Page', points.current_page.to_s)
    response.set_header('X-Total-Pages', points.total_pages.to_s)

    render json: points
  end

  def destroy
    point = current_api_user.tracked_points.find(params[:id])
    point.destroy

    render json: { message: 'Point deleted successfully' }
  end
end
