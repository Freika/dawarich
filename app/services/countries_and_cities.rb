# frozen_string_literal: true

class CountriesAndCities
  CountryData = Struct.new(:country, :cities, keyword_init: true)
  CityData = Struct.new(:city, :points, :timestamp, :stayed_for, keyword_init: true)

  FLYOVER_ALTITUDE_THRESHOLD_METERS = 1000
  FLYOVER_VELOCITY_THRESHOLD_KMH = 250
  MS_TO_KMH = 3.6

  def initialize(points, min_minutes_spent_in_city: 60, max_gap_minutes: 120)
    @points = points
    @min_minutes_spent_in_city = min_minutes_spent_in_city
    @max_gap_minutes = max_gap_minutes
  end

  def call
    points
      .reject { |point| point[:country_name].nil? || point[:city].nil? || flyover?(point) }
      .group_by { |point| canonical_country_name(point) }
      .transform_values { |country_points| process_country_points(country_points) }
      .map { |country, cities| CountryData.new(country: country, cities: cities) }
  end

  private

  attr_reader :points, :min_minutes_spent_in_city, :max_gap_minutes

  def flyover?(point)
    altitude = point[:altitude]
    velocity_ms = point[:velocity].to_f

    altitude.to_i > FLYOVER_ALTITUDE_THRESHOLD_METERS ||
      (velocity_ms * MS_TO_KMH) > FLYOVER_VELOCITY_THRESHOLD_KMH
  end

  def canonical_country_name(point)
    country_id = point[:country_id]
    return point[:country_name] if country_id.blank?

    country_names_by_id[country_id] || point[:country_name]
  end

  def country_names_by_id
    @country_names_by_id ||= begin
      ids = points.filter_map { |p| p[:country_id] }.uniq
      ids.any? ? Country.where(id: ids).pluck(:id, :name).to_h : {}
    end
  end

  def process_country_points(country_points)
    country_points
      .group_by { |point| point[:city] }
      .transform_values { |city_points| create_city_data_if_valid(city_points) }
      .values
      .compact
  end

  def create_city_data_if_valid(city_points)
    timestamps = city_points.pluck(:timestamp)
    duration = calculate_duration_in_minutes(timestamps)
    city = city_points.first[:city]
    points_count = city_points.size

    build_city_data(city, points_count, timestamps, duration)
  end

  def build_city_data(city, points_count, timestamps, duration)
    return nil if duration < min_minutes_spent_in_city

    CityData.new(
      city: city,
      points: points_count,
      timestamp: timestamps.max,
      stayed_for: duration
    )
  end

  def calculate_duration_in_minutes(timestamps)
    return 0 if timestamps.size < 2

    sorted = timestamps.sort
    total_seconds = 0
    gap_threshold_seconds = max_gap_minutes * 60

    sorted.each_cons(2) do |prev_ts, curr_ts|
      interval_seconds = curr_ts - prev_ts
      total_seconds += interval_seconds if interval_seconds < gap_threshold_seconds
    end

    total_seconds / 60
  end
end
