# frozen_string_literal: true

class MapController < ApplicationController
  before_action :authenticate_user!

  def index
    @points = filtered_points
    @coordinates = build_coordinates
    @tracks = build_tracks
    @distance = calculate_distance
    @start_at = parsed_start_at
    @end_at = parsed_end_at
    @years = years_range
    @points_number = points_count
  end

  private

  def filtered_points
    points.where('timestamp >= ? AND timestamp <= ?', start_at, end_at)
  end

  def build_coordinates
    @points.pluck(:lonlat, :battery, :altitude, :timestamp, :velocity, :id, :country, :track_id)
           .map { |lonlat, *rest| [lonlat.y, lonlat.x, *rest.map(&:to_s)] }
  end

  def extract_track_ids
    @coordinates.map { |coord| coord[8]&.to_i }.compact.uniq.reject(&:zero?)
  end

  def build_tracks
    track_ids = extract_track_ids
    TrackSerializer.new(current_user, track_ids).call
  end

  def calculate_distance
    distance = 0

    @coordinates.each_cons(2) do
      distance += Geocoder::Calculations.distance_between(
        [_1[0], _1[1]], [_2[0], _2[1]], units: current_user.safe_settings.distance_unit.to_sym
      )
    end

    distance_in_meters = case current_user.safe_settings.distance_unit.to_s
                         when 'mi'
                           distance * 1609.344 # miles to meters
                         else
                           distance * 1000 # km to meters
                         end

    distance_in_meters.round
  end

  def parsed_start_at
    Time.zone.at(start_at)
  end

  def parsed_end_at
    Time.zone.at(end_at)
  end

  def years_range
    (parsed_start_at.year..parsed_end_at.year).to_a
  end

  def points_count
    @coordinates.count
  end

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
