# frozen_string_literal: true

class Stat < ApplicationRecord
  include DistanceConvertible
  include Shareable

  validates :year, :month, presence: true

  belongs_to :user

  def distance_by_day
    monthly_points = points
    calculate_daily_distances(monthly_points)
  end

  def self.year_distance(year, user)
    stats_by_month = where(year:, user:).order(:month).index_by(&:month)

    (1..12).map do |month|
      month_name = Date::MONTHNAMES[month]
      distance = stats_by_month[month]&.distance || 0

      [month_name, distance]
    end
  end

  def points
    user.points
        .without_raw_data
        .where(timestamp: timespan)
        .order(timestamp: :asc)
  end

  def hexagons_available?
    h3_hex_ids.present? &&
      (h3_hex_ids.is_a?(Hash) || h3_hex_ids.is_a?(Array)) &&
      h3_hex_ids.any?
  end

  def calculate_data_bounds
    start_date = Date.new(year, month, 1).beginning_of_day
    end_date = start_date.end_of_month.end_of_day

    points_relation = user.points.where(timestamp: start_date.to_i..end_date.to_i)
    point_count = points_relation.count

    return nil if point_count.zero?

    bounds_result = ActiveRecord::Base.connection.exec_query(
      "SELECT MIN(ST_Y(lonlat::geometry)) as min_lat, MAX(ST_Y(lonlat::geometry)) as max_lat,
              MIN(ST_X(lonlat::geometry)) as min_lng, MAX(ST_X(lonlat::geometry)) as max_lng
       FROM points
       WHERE user_id = $1
       AND timestamp BETWEEN $2 AND $3
       AND lonlat IS NOT NULL",
      'data_bounds_query',
      [user.id, start_date.to_i, end_date.to_i]
    ).first

    {
      min_lat: bounds_result['min_lat'].to_f,
      max_lat: bounds_result['max_lat'].to_f,
      min_lng: bounds_result['min_lng'].to_f,
      max_lng: bounds_result['max_lng'].to_f,
      point_count: point_count
    }
  end

  def process!
    Stats::CalculatingJob.perform_later(user.id, year, month)
  end

  private

  def timespan
    DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month
  end

  def calculate_daily_distances(monthly_points)
    Stats::DailyDistanceQuery.new(monthly_points, timespan, user_timezone).call
  end

  def user_timezone
    # Future: Once user.timezone column exists, uncomment the line below
    # user.timezone.presence || Time.zone.name

    # For now, use application timezone
    Time.zone.name
  end
end
