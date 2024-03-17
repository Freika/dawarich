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
        .group_by { |city, _| city }
        .transform_values do |cities|
          {
            points: cities.count,
            timestamp: cities.map(&:last).max # Get the maximum timestamp
          }
        end
    end
  end


  def filter_cities(mapped_with_cities)
    # Remove cities with less than MINIMUM_POINTS_IN_CITY
    mapped_with_cities.transform_values do |cities|
      cities.reject { |_, data| data[:points] < MINIMUM_POINTS_IN_CITY }
    end
  end

  def normalize_result(hash)
    hash.map do |country, cities|
      {
        country: country,
        cities: cities.map { |city, data| { city: city, points: data[:points], timestamp: data[:timestamp] } }
      }
    end
  end
end
