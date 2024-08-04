# frozen_string_literal: true

class Api::V1::PointsController < ApplicationController
  skip_forgery_protection
  before_action :authenticate_api_key

  def index
    start_at = params[:start_at]&.to_datetime&.to_i
    end_at = params[:end_at]&.to_datetime&.to_i || Time.zone.now.to_i

    points = current_api_user.tracked_points.where(timestamp: start_at..end_at)

    render json: points
  end

  def destroy
    point = current_api_user.tracked_points.find(params[:id])
    point.destroy

    render json: { message: 'Point deleted successfully' }
  end
end
