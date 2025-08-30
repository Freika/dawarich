# frozen_string_literal: true

module LocationSearch
  class PointFinder
    def initialize(user, params = {})
      @user = user
      @query = params[:query]
      @limit = params[:limit] || 50
      @date_from = params[:date_from]
      @date_to = params[:date_to]
      @radius_override = params[:radius_override]
    end

    def call
      return empty_result if @query.blank?

      geocoded_locations = geocoding_service.search(@query)
      return empty_result if geocoded_locations.empty?

      find_matching_points(geocoded_locations)
    end

    private

    def geocoding_service
      @geocoding_service ||= LocationSearch::GeocodingService.new
    end

    def find_matching_points(geocoded_locations)
      results = []
      
      geocoded_locations.each do |location|
        matching_points = spatial_matcher.find_points_near(
          @user,
          location[:lat],
          location[:lon],
          determine_search_radius(location),
          date_filter_options
        )
        
        next if matching_points.empty?
        
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

    def determine_search_radius(location)
      return @radius_override if @radius_override.present?

      # Smart radius selection based on place type
      place_type = location[:type]&.downcase || ''
      
      case place_type
      when /shop|store|restaurant|cafe|supermarket|mall/
        75  # meters - specific businesses
      when /street|road|avenue|boulevard/
        50  # meters - street addresses
      when /neighborhood|district|area/
        300 # meters - areas
      when /city|town|village/
        1000 # meters - cities
      else
        100 # meters - default for unknown types
      end
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