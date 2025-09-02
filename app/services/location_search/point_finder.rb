# frozen_string_literal: true

module LocationSearch
  class PointFinder
    def initialize(user, params = {})
      @user = user
      @query = params[:query]
      @latitude = params[:latitude]
      @longitude = params[:longitude]
      @name = params[:name] || 'Selected Location'
      @address = params[:address] || ''
      @limit = params[:limit] || 50
      @date_from = params[:date_from]
      @date_to = params[:date_to]
      @radius_override = params[:radius_override]
    end

    def call
      if coordinate_search?
        return coordinate_based_search
      elsif @query.present?
        return text_based_search
      else
        return empty_result
      end
    end

    private

    def coordinate_search?
      @latitude.present? && @longitude.present?
    end

    def coordinate_based_search
      Rails.logger.info "LocationSearch: Coordinate-based search at [#{@latitude}, #{@longitude}] for '#{@name}'"

      # Create a single location object with the provided coordinates
      location = {
        lat: @latitude,
        lon: @longitude,
        name: @name,
        address: @address,
        type: 'coordinate_search'
      }

      find_matching_points([location])
    end

    def text_based_search
      return empty_result if @query.blank?

      geocoded_locations = geocoding_service.search(@query)

      # Debug: Log geocoding results
      Rails.logger.info "LocationSearch: Geocoding '#{@query}' returned #{geocoded_locations.length} locations"
      geocoded_locations.each_with_index do |loc, idx|
        Rails.logger.info "LocationSearch: [#{idx}] #{loc[:name]} at [#{loc[:lat]}, #{loc[:lon]}] - #{loc[:address]}"
      end

      return empty_result if geocoded_locations.empty?

      find_matching_points(geocoded_locations)
    end

    def geocoding_service
      @geocoding_service ||= LocationSearch::GeocodingService.new
    end

    def find_matching_points(geocoded_locations)
      results = []

      geocoded_locations.each do |location|
        # Debug: Log the geocoded location
        Rails.logger.info "LocationSearch: Searching for points near #{location[:name]} at [#{location[:lat]}, #{location[:lon]}]"

        matching_points = spatial_matcher.find_points_near(
          @user,
          location[:lat],
          location[:lon],
          @radius_override || 500, # Allow radius override, default 500 meters
          date_filter_options
        )

        # Debug: Log the number of matching points found
        Rails.logger.info "LocationSearch: Found #{matching_points.length} points within #{@radius_override || 500}m radius"

        if matching_points.empty?
          # Try with a larger radius to see if there are any points nearby
          wider_search = spatial_matcher.find_points_near(
            @user,
            location[:lat],
            location[:lon],
            1000, # 1km radius for debugging
            date_filter_options
          )
          Rails.logger.info "LocationSearch: Found #{wider_search.length} points within 1000m radius (debug)"
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
        query: @query,
        locations: results,
        total_locations: results.length,
        search_metadata: {
          geocoding_provider: geocoding_service.provider_name,
          candidates_found: geocoded_locations.length,
          search_time_ms: nil # TODO: implement timing
        }
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

    def empty_result
      {
        query: @query,
        locations: [],
        total_locations: 0,
        search_metadata: {
          geocoding_provider: nil,
          candidates_found: 0,
          search_time_ms: 0
        }
      }
    end
  end
end
