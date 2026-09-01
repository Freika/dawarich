# frozen_string_literal: true

class CountriesAndCities
  CountryData = Struct.new(:country, :cities, keyword_init: true)
  CityData = Struct.new(:city, :points, :timestamp, :stayed_for, keyword_init: true)

  FLYOVER_VELOCITY_THRESHOLD_KMH = 500
  MS_TO_KMH = 3.6
  BRIDGE_CAP_SECONDS = 7 * 24 * 60 * 60

  def initialize(points, min_minutes_spent_in_city: 60)
    @points = points
    @min_minutes_spent_in_city = min_minutes_spent_in_city
  end

  def call
    presence_runs
      .group_by { |run| run[:country] }
      .transform_values { |country_runs| build_cities(country_runs) }
      .map { |country, cities| CountryData.new(country: country, cities: cities) }
  end

  private

  attr_reader :points, :min_minutes_spent_in_city

  def tracked_points
    @tracked_points ||=
      points
      .reject { |point| point[:country_name].nil? || point[:city].nil? || flyover?(point) }
      .sort_by { |point| point[:timestamp] }
  end

  def presence_runs
    tracked_points
      .slice_when { |previous, current| separate_runs?(previous, current) }
      .map { |run_points| build_run(run_points) }
  end

  def separate_runs?(previous, current)
    previous[:city] != current[:city] ||
      canonical_country_name(previous) != canonical_country_name(current) ||
      (current[:timestamp] - previous[:timestamp]) > BRIDGE_CAP_SECONDS
  end

  def build_run(run_points)
    timestamps = run_points.map { |point| point[:timestamp] }

    {
      country: canonical_country_name(run_points.first),
      city: run_points.first[:city],
      points: run_points.size,
      last_timestamp: timestamps.max,
      duration_seconds: timestamps.max - timestamps.min
    }
  end

  def build_cities(country_runs)
    country_runs
      .group_by { |run| run[:city] }
      .filter_map { |city, city_runs| build_city_data(city, city_runs) }
  end

  def build_city_data(city, city_runs)
    duration = city_runs.sum { |run| run[:duration_seconds] } / 60
    return nil if duration < min_minutes_spent_in_city

    CityData.new(
      city: city,
      points: city_runs.sum { |run| run[:points] },
      timestamp: city_runs.map { |run| run[:last_timestamp] }.max,
      stayed_for: duration
    )
  end

  def flyover?(point)
    (point[:velocity].to_f * MS_TO_KMH) > FLYOVER_VELOCITY_THRESHOLD_KMH
  end

  def canonical_country_name(point)
    country_id = point[:country_id]
    return point[:country_name] if country_id.blank?

    country_names_by_id[country_id] || point[:country_name]
  end

  def country_names_by_id
    @country_names_by_id ||= begin
      ids = tracked_points.filter_map { |point| point[:country_id] }.uniq
      ids.any? ? Country.where(id: ids).pluck(:id, :name).to_h : {}
    end
  end
end
