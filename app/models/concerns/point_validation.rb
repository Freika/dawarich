# frozen_string_literal: true

module PointValidation
  extend ActiveSupport::Concern

  # Check if a point with the same coordinates, timestamp, and user_id already exists
  def point_exists?(params, user_id)
    # Ensure the coordinates are valid
    longitude = params[:longitude].to_f
    latitude = params[:latitude].to_f

    # Check if longitude and latitude are valid values
    return false if longitude.zero? && latitude.zero?
    return false if longitude.abs > 180 || latitude.abs > 90

    # Use where with parameter binding and then exists?
    Point.where(
      'ST_SetSRID(ST_MakePoint(?, ?), 4326) = lonlat AND timestamp = ? AND user_id = ?',
      longitude, latitude, params[:timestamp].to_i, user_id
    ).exists?
  end
end
