# frozen_string_literal: true

class MapController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = points.where('timestamp >= ? AND timestamp <= ?', start_at, end_at)

    @coordinates =
      @points.pluck(:lonlat, :battery, :altitude, :timestamp, :velocity, :id, :country, :track_id)
             .map { |lonlat, *rest| [lonlat.y, lonlat.x, *rest.map(&:to_s)] }
    @tracks = TrackSerializer.new(current_user, @coordinates).call
    @distance = distance
    @start_at = Time.zone.at(start_at)
    @end_at = Time.zone.at(end_at)
    @years = (@start_at.year..@end_at.year).to_a
    @points_number = @coordinates.count
  end

  private

  def start_at
    return Time.zone.parse(params[:start_at]).to_i if params[:start_at].present?
    return Time.zone.at(points.last.timestamp).beginning_of_day.to_i if points.any?

    Time.zone.today.beginning_of_day.to_i
  end

  def end_at
    return Time.zone.parse(params[:end_at]).to_i if params[:end_at].present?
    return Time.zone.at(points.last.timestamp).end_of_day.to_i if points.any?

    Time.zone.today.end_of_day.to_i
  end

  def distance
    @distance ||= 0

    @coordinates.each_cons(2) do
      @distance += Geocoder::Calculations.distance_between(
        [_1[0], _1[1]], [_2[0], _2[1]], units: current_user.safe_settings.distance_unit.to_sym
      )
    end

    @distance.round(1)
  end

  def points
    params[:import_id] ? points_from_import : points_from_user
  end

  def points_from_import
    current_user.imports.find(params[:import_id]).points.without_raw_data.order(timestamp: :asc)
  end

  def points_from_user
    current_user.tracked_points.without_raw_data.order(timestamp: :asc)
  end
end
