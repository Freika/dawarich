# frozen_string_literal: true

module PointValidation
  extend ActiveSupport::Concern

  def point_exists?(params, user_id)
    Point.where(
      lonlat: params[:lonlat],
      timestamp: params[:timestamp].to_i,
      tracker_id: params[:tracker_id],
      user_id:
    ).exists?
  end
end
