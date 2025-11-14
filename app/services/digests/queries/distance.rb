# frozen_string_literal: true

class Digests::Queries::Distance
  def initialize(user, date_range)
    @user = user
    @date_range = date_range
    @start_timestamp = date_range.begin.to_i
    @end_timestamp = date_range.end.to_i
  end

  def call
    points = fetch_points

    {
      total_distance_km: calculate_total_distance(points),
      daily_average_km: calculate_daily_average(points),
      max_distance_day: find_max_distance_day(points)
    }
  end

  private

  def fetch_points
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .order(timestamp: :asc)
  end

  def calculate_total_distance(points)
    return 0 if points.empty?

    total = 0
    points.each_cons(2) do |p1, p2|
      total += Geocoder::Calculations.distance_between(
        [p1.latitude, p1.longitude],
        [p2.latitude, p2.longitude],
        units: :km
      )
    end
    total.round(2)
  end

  def calculate_daily_average(points)
    total = calculate_total_distance(points)
    days = (@date_range.end.to_date - @date_range.begin.to_date).to_i + 1
    (total / days).round(2)
  rescue ZeroDivisionError
    0
  end

  def find_max_distance_day(points)
    # Group by day and calculate distance for each day
    daily_distances = points.group_by { |p| Time.at(p.timestamp).to_date }
                           .transform_values { |day_points| calculate_total_distance(day_points) }

    max_day = daily_distances.max_by { |_date, distance| distance }
    max_day ? { date: max_day[0], distance_km: max_day[1] } : nil
  end
end
