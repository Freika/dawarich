# frozen_string_literal: true

class Stat < ApplicationRecord
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
    user.tracked_points
        .without_raw_data
        .where(timestamp: timespan)
        .order(timestamp: :asc)
  end

  private

  def timespan
    DateTime.new(year, month).beginning_of_month..DateTime.new(year, month).end_of_month
  end

  def calculate_daily_distances(monthly_points)
    timespan.to_a.map.with_index(1) do |day, index|
      daily_points = filter_points_for_day(monthly_points, day)
      distance = Point.total_distance(daily_points, user.safe_settings.distance_unit)
      [index, distance.round(2)]
    end
  end

  def filter_points_for_day(points, day)
    beginning_of_day = day.beginning_of_day.to_i
    end_of_day = day.end_of_day.to_i

    points.select { |p| p.timestamp.between?(beginning_of_day, end_of_day) }
  end
end
