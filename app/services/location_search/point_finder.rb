# frozen_string_literal: true

module LocationSearch
  class PointFinder
    def initialize(user, params = {})
      @user = user
      @latitude = params[:latitude]
      @longitude = params[:longitude]
      @limit = params[:limit] || 50
      @date_from = params[:date_from]
      @date_to = params[:date_to]
      @radius_override = params[:radius_override]
    end

    def call
      return empty_result unless valid_coordinates?

      location = {
        lat: @latitude,
        lon: @longitude,
        type: 'coordinate_search'
      }

      find_matching_points([location])
    end

    private

    def find_matching_points(geocoded_locations)
      results = []

      geocoded_locations.each do |location|
        search_radius = @radius_override || determine_search_radius(location[:type])

        matching_points = spatial_matcher.find_points_near(
          @user,
          location[:lat],
          location[:lon],
          search_radius,
          date_filter_options
        )

        if matching_points.empty?
          wider_search = spatial_matcher.find_points_near(
            @user,
            location[:lat],
            location[:lon],
            1000, # 1km radius for debugging
            date_filter_options
          )

          next
        end

        visits = result_aggregator.group_points_into_visits(matching_points)

        results << {
          place_name: location[:name],
          coordinates: [location[:lat], location[:lon]],
          address: location[:address],
          total_visits: visits.length,
          first_visit: visits.first[:date],
          last_visit: visits.last[:date],
          visits: visits.take(@limit)
        }
      end

      {
        locations: results,
        total_locations: results.length,
        search_metadata: {}
      }
    end

    def spatial_matcher
      @spatial_matcher ||= LocationSearch::SpatialMatcher.new
    end

    def result_aggregator
      @result_aggregator ||= LocationSearch::ResultAggregator.new
    end

    def date_filter_options
      {
        date_from: @date_from,
        date_to: @date_to
      }
    end

    def determine_search_radius(location_type)
      case location_type.to_s.downcase
      when 'shop', 'store', 'retail'
        75   # Small radius for specific shops
      when 'restaurant', 'cafe', 'food'
        75   # Small radius for specific restaurants
      when 'building', 'house', 'address'
        50   # Very small radius for specific addresses
      when 'street', 'road'
        50   # Very small radius for streets
      when 'neighbourhood', 'neighborhood', 'district', 'suburb'
        300  # Medium radius for neighborhoods
      when 'city', 'town', 'village'
        1000 # Large radius for cities
      else
        500  # Default radius for unknown types
      end
    end

    def valid_coordinates?
      @latitude.present? && @longitude.present? &&
        @latitude.to_f.between?(-90, 90) && @longitude.to_f.between?(-180, 180)
    end

    def empty_result
      {
        locations: [],
        total_locations: 0,
        search_metadata: {}
      }
    end
  end
end
