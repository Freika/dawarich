# frozen_string_literal: true

class PointsController < ApplicationController
  include SafeTimestampParser

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
    point_ids = params[:point_ids]&.compact&.reject(&:blank?)

    if point_ids.blank?
      redirect_to points_url(preserved_params),
                  alert: 'No points selected.',
                  status: :see_other and return
    end

    current_user.points.where(id: point_ids).destroy_all

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

    safe_timestamp(params[:start_at])
  end

  def end_at
    return Time.zone.today.end_of_day.to_i if params[:end_at].nil?

    safe_timestamp(params[:end_at])
  end

  def points
    params[:import_id].present? ? import_points : user_points
  end

  def import_points
    current_user.imports.find(params[:import_id]).points
  end

  def user_points
    current_user.points
  end

  def order_by
    params[:order_by] || 'desc'
  end

  def preserved_params
    params.to_enum.to_h.with_indifferent_access.slice(:start_at, :end_at, :order_by, :import_id)
  end
end
