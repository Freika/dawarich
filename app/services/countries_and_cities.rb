# frozen_string_literal: true

class CountriesAndCities
  def initialize(points)
    @points = points
  end

  def call
    grouped_records = group_points
    mapped_with_cities = map_with_cities(grouped_records)

    filtered_cities = filter_cities(mapped_with_cities)

    normalize_result(filtered_cities)
  end

  private

  attr_reader :points

  def group_points
    points.group_by(&:country)
  end

  def map_with_cities(grouped_records)
    grouped_records.transform_values do |grouped_points|
      grouped_points
        .pluck(:city, :timestamp) # Extract city and timestamp
        .delete_if { _1.first.nil? } # Remove records without city
        .group_by { |city, _| city } # Group by city
        .transform_values do |cities|
          {
            points: cities.count,
            last_timestamp: cities.map(&:last).max, # Get the maximum timestamp
            stayed_for: ((cities.map(&:last).max - cities.map(&:last).min).to_i / 60) # Calculate the time stayed in minutes
          }
        end
    end
  end

  def filter_cities(mapped_with_cities)
    # Remove cities where user stayed for less than 1 hour
    mapped_with_cities.transform_values do |cities|
      cities.reject { |_, data| data[:stayed_for] < MIN_MINUTES_SPENT_IN_CITY }
    end
  end

  def normalize_result(hash)
    hash.map do |country, cities|
      {
        country:,
        cities: cities.map do |city, data|
          { city:, points: data[:points], timestamp: data[:last_timestamp], stayed_for: data[:stayed_for]}
        end
      }
    end
  end
end
