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
      .transform_values { |country_points| process_country_points(country_points) }
      .map { |country, cities| CountryData.new(country: country, cities: cities) }
  end

  private

  attr_reader :points

  def process_country_points(country_points)
    country_points
      .group_by(&:city)
      .transform_values { |city_points| create_city_data_if_valid(city_points) }
      .values
      .compact
  end

  def create_city_data_if_valid(city_points)
    timestamps = city_points.pluck(:timestamp)
    duration = calculate_duration_in_minutes(timestamps)
    city = city_points.first.city
    points_count = city_points.size

    build_city_data(city, points_count, timestamps, duration)
  end

  def build_city_data(city, points_count, timestamps, duration)
    return nil if duration < ::MIN_MINUTES_SPENT_IN_CITY

    CityData.new(
      city: city,
      points: points_count,
      timestamp: timestamps.max,
      stayed_for: duration
    )
  end

  def calculate_duration_in_minutes(timestamps)
    ((timestamps.max - timestamps.min).to_i / 60)
  end
end
