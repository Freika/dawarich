# frozen_string_literal: true

class Map::LeafletController < ApplicationController
  include SafeTimestampParser

  before_action :authenticate_user!
  layout 'map', only: :index

  def index
    @points = filtered_points
    @coordinates = build_coordinates
    @tracks = build_tracks
    @distance = calculate_distance
    @start_at = parsed_start_at
    @end_at = parsed_end_at
    @years = years_range
    @points_number = points_count
    @features = DawarichSettings.features
    @home_coordinates = current_user.home_place_coordinates
  end

  private

  def filtered_points
    points.where('timestamp >= ? AND timestamp <= ?', start_at, end_at)
  end

  def build_coordinates
    @points.pluck(:lonlat, :battery, :altitude, :timestamp, :velocity, :id, :country_name, :track_id)
           .map { |lonlat, *rest| [lonlat.y, lonlat.x, *rest.map(&:to_s)] }
  end

  def extract_track_ids
    @coordinates.map { |coord| coord[8]&.to_i }.compact.uniq.reject(&:zero?)
  end

  def build_tracks
    track_ids = extract_track_ids

    TracksSerializer.new(current_user, track_ids).call
  end

  def calculate_distance
    return 0 if @points.count(:id) < 2

    # Use PostGIS window function for efficient distance calculation
    # This is O(1) database operation vs O(n) Ruby iteration
    import_filter = params[:import_id].present? ? 'AND import_id = :import_id' : ''

    sql = <<~SQL.squish
      SELECT COALESCE(SUM(distance_m) / 1000.0, 0) as total_km FROM (
        SELECT ST_Distance(
          lonlat::geography,
          LAG(lonlat::geography) OVER (ORDER BY timestamp)
        ) as distance_m
        FROM points
        WHERE user_id = :user_id
          AND timestamp >= :start_at
          AND timestamp <= :end_at
          #{import_filter}
      ) distances
    SQL

    query_params = { user_id: current_user.id, start_at: start_at, end_at: end_at }
    query_params[:import_id] = params[:import_id] if params[:import_id].present?

    result = Point.connection.select_value(
      ActiveRecord::Base.sanitize_sql_array([sql, query_params])
    )

    result&.to_f&.round || 0
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
    return safe_timestamp(params[:start_at]) if params[:start_at].present?

    if points.any?
      point_date = TimezoneHelper.timestamp_to_date(points.last.timestamp, user_timezone)
      return TimezoneHelper.day_bounds(point_date, user_timezone).first
    end

    TimezoneHelper.today_start_timestamp(user_timezone)
  end

  def end_at
    return safe_timestamp(params[:end_at]) if params[:end_at].present?

    if points.any?
      point_date = TimezoneHelper.timestamp_to_date(points.last.timestamp, user_timezone)
      return TimezoneHelper.day_bounds(point_date, user_timezone).last
    end

    TimezoneHelper.today_end_timestamp(user_timezone)
  end

  def user_timezone
    current_user.timezone.presence || TimezoneHelper::DEFAULT_TIMEZONE
  end

  def points
    params[:import_id] ? points_from_import : points_from_user
  end

  def points_from_import
    current_user.imports.find(params[:import_id]).points.without_raw_data.order(timestamp: :asc)
  end

  def points_from_user
    current_user.points.without_raw_data.order(timestamp: :asc)
  end
end
