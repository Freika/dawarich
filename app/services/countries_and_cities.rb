# frozen_string_literal: true

class CountriesAndCities
  CityStats = Struct.new(:points, :last_timestamp, :stayed_for, keyword_init: true)
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
      .transform_values do |city_points|
        timestamps = city_points.map(&:timestamp)
        build_city_data(city_points.first.city, city_points.size, timestamps)
      end
      .values
  end

  def build_city_data(city, points_count, timestamps)
    CityData.new(
      city: city,
      points: points_count,
      timestamp: timestamps.max,
      stayed_for: calculate_duration_in_minutes(timestamps)
    )
  end

  def calculate_duration_in_minutes(timestamps)
    ((timestamps.max - timestamps.min).to_i / 60)
  end
end
