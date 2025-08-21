# frozen_string_literal: true

class Stat < ApplicationRecord
  include DistanceConvertible

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

  private

  def timespan
    DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month
  end

  def calculate_daily_distances(monthly_points)
    Stats::DailyDistanceQuery.new(monthly_points, timespan, user_timezone).call
  end

  private

  def user_timezone
    # Future: Once user.timezone column exists, uncomment the line below
    # user.timezone.presence || Time.zone.name

    # For now, use application timezone
    Time.zone.name
  end
end
