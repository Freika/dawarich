# frozen_string_literal: true

class MapController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = points
              .without_raw_data
              .where('timestamp >= ? AND timestamp <= ?', start_at, end_at)
              .order(timestamp: :asc)

    @countries_and_cities = CountriesAndCities.new(@points).call
    @coordinates =
      @points.pluck(:latitude, :longitude, :battery, :altitude, :timestamp, :velocity, :id)
             .map { [_1.to_f, _2.to_f, _3.to_s, _4.to_s, _5.to_s, _6.to_s, _7.to_s] }
    @distance = distance
    @start_at = Time.zone.at(start_at)
    @end_at = Time.zone.at(end_at)
    @years = (@start_at.year..@end_at.year).to_a
  end

  private

  def start_at
    return Time.zone.today.beginning_of_day.to_i if params[:start_at].nil?

    Time.zone.parse(params[:start_at]).to_i
  end

  def end_at
    return Time.zone.today.end_of_day.to_i if params[:end_at].nil?

    Time.zone.parse(params[:end_at]).to_i
  end

  def distance
    @distance ||= 0

    @coordinates.each_cons(2) do
      @distance += Geocoder::Calculations.distance_between(
        [_1[0], _1[1]], [_2[0], _2[1]], units: DISTANCE_UNIT
      )
    end

    @distance.round(1)
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
end
