# frozen_string_literal: true

class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    @points =
      current_user
      .tracked_points
      .without_raw_data
      .where('timestamp >= ? AND timestamp <= ?', start_at, end_at)
      .order(timestamp: :asc)
      .paginate(page: params[:page], per_page: 50)

    @start_at = Time.zone.at(start_at)
    @end_at = Time.zone.at(end_at)
  end

  def bulk_destroy
    current_user.tracked_points.where(id: params[:point_ids].compact).destroy_all

    redirect_to points_url, notice: 'Points were successfully destroyed.', status: :see_other
  end

  private

  def point_params
    params.fetch(:point, {})
  end

  def start_at
    return 1.month.ago.beginning_of_day.to_i if params[:start_at].nil?

    Time.zone.parse(params[:start_at]).to_i
  end

  def end_at
    return Time.zone.today.end_of_day.to_i if params[:end_at].nil?

    Time.zone.parse(params[:end_at]).to_i
  end
end
