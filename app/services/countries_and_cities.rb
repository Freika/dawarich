# frozen_string_literal: true

class CountriesAndCities
  CountryData = Struct.new(:country, :cities, keyword_init: true)
  CityData = Struct.new(:city, :points, :timestamp, :stayed_for, keyword_init: true)

  def initialize(points)
    @points = points
  end

  def call
    points
      .reject { |point| point.country.nil? || point.city.nil? }
      .group_by(&:country)
      .map do |country, country_points|
        cities = process_country_points(country_points)
        CountryData.new(country: country, cities: cities) if cities.any?
      end.compact
  end

  private

  attr_reader :points

# Step 1: Process points to group by consecutive cities and time
  def group_points_with_consecutive_cities(country_points)
    sorted_points = country_points.sort_by(&:timestamp)

    sessions = []
    current_session = []

    sorted_points.each_with_index do |point, index|
      if current_session.empty?
        current_session << point
        next
      end

      prev_point = sorted_points[index - 1]

      # Split session if city changes or time gap exceeds the threshold
      if point.city != prev_point.city
        sessions << current_session
        current_session = []
      end

      current_session << point
    end

    sessions << current_session unless current_session.empty?
    sessions
  end

  # Step 2: Filter sessions that don't meet the minimum minutes per city
  def filter_sessions(sessions)
    sessions.map do |session|
      end_time = session.last.timestamp
      duration = (end_time - session.first.timestamp) / 60 # Convert seconds to minutes

      if duration >= MIN_MINUTES_SPENT_IN_CITY
        CityData.new(
          city: session.first.city,
          points: session.size,
          timestamp: end_time,
          stayed_for: duration
        )
      end
    end.compact
  end

  # Process points for each country
  def process_country_points(country_points)
    sessions = group_points_with_consecutive_cities(country_points)
    filter_sessions(sessions)
  end
end
