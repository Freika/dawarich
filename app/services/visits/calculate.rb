# frozen_string_literal: true

class Visits::Calculate
  def initialize(points)
    @points = points
  end

  def call
    normalize_result(city_visits)
  end

  private

  attr_reader :points

  def group_points
    points.sort_by(&:timestamp).reject { _1.city.nil? }.group_by(&:country)
  end

  def city_visits
    group_points.transform_values do |grouped_points|
      grouped_points
        .group_by(&:city)
        .transform_values { |city_points| identify_consecutive_visits(city_points) }
    end
  end

  def identify_consecutive_visits(city_points)
    visits = []
    current_visit = []

    city_points.each_cons(2) do |point1, point2|
      time_diff = (point2.timestamp - point1.timestamp) / 60

      if time_diff <= MIN_MINUTES_SPENT_IN_CITY
        current_visit << point1 unless current_visit.include?(point1)
        current_visit << point2
      else
        visits << create_visit(current_visit) if current_visit.size > 1
        current_visit = []
      end
    end

    visits << create_visit(current_visit) if current_visit.size > 1
    visits
  end

  def create_visit(points)
    {
      city: points.first.city,
      points:,
      stayed_for: calculate_stayed_time(points),
      last_timestamp: points.last.timestamp
    }
  end

  def calculate_stayed_time(points)
    return 0 if points.empty?

    min_time = points.first.timestamp
    max_time = points.last.timestamp
    ((max_time - min_time) / 60).round
  end

  def normalize_result(hash)
    hash.map do |country, cities|
      {
        country:,
        cities: cities.values.flatten
                      .select { |visit| visit[:stayed_for] >= MIN_MINUTES_SPENT_IN_CITY }
                      .map do |visit|
                        {
                          city: visit[:city],
                          points: visit[:points].count,
                          timestamp: visit[:last_timestamp],
                          stayed_for: visit[:stayed_for]
                        }
                      end
      }
    end.reject { |entry| entry[:cities].empty? }
  end
end
