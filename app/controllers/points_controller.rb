# frozen_string_literal: true

class PointsController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = points
              .without_raw_data
              .where(timestamp: start_at..end_at)
              .order(timestamp: order_by)
              .page(params[:page])
              .per(50)

    @start_at = Time.zone.at(start_at)
    @end_at = Time.zone.at(end_at)

    @imports = current_user.imports.order(created_at: :desc)
  end

  def bulk_destroy
    current_user.tracked_points.where(id: params[:point_ids].compact).destroy_all

    redirect_to points_url(preserved_params),
                notice: 'Points were successfully destroyed.',
                status: :see_other
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

  def points
    params[:import_id] ? points_from_import : points_from_user
  end

  def points_from_import
    current_user.imports.find(params[:import_id]).points
  end

  def points_from_user
    current_user.tracked_points
  end

  def order_by
    params[:order_by] || 'desc'
  end

  def preserved_params
    params.to_enum.to_h.with_indifferent_access.slice(:start_at, :end_at, :order_by, :import_id)
  end
end
