# frozen_string_literal: true

module LocationSearch
  class GeocodingService
    MAX_RESULTS = 10

    def initialize(query)
      @query = query
    end

    def search
      return [] if query.blank?

      perform_geocoding_search(query)
    rescue StandardError => e
      Rails.logger.error "Geocoding search failed for query '#{query}': #{e.message}"
      []
    end

    def provider_name
      Geocoder.config.lookup.to_s.capitalize
    end

    private

    attr_reader :query

    def perform_geocoding_search(query)
      results = Geocoder.search(query, limit: MAX_RESULTS)
      return [] if results.blank?

      normalize_geocoding_results(results)
    end

    def normalize_geocoding_results(results)
      normalized_results = results.filter_map do |result|
        lat = result.latitude.to_f
        lon = result.longitude.to_f

        next unless valid_coordinates?(lat, lon)

        {
          lat: lat,
          lon: lon,
          name: result.address&.split(',')&.first || 'Unknown location',
          address: result.address || '',
          type: result.data&.dig('type') || result.data&.dig('class') || 'unknown',
          provider_data: {
            osm_id: result.data&.dig('osm_id'),
            place_rank: result.data&.dig('place_rank'),
            importance: result.data&.dig('importance')
          }
        }
      end

      deduplicate_results(normalized_results)
    end

    def deduplicate_results(results)
      deduplicated = []

      results.each do |result|
        # Check if there's already a result within 100m
        duplicate = deduplicated.find do |existing|
          distance = calculate_distance_in_meters(
            result[:lat], result[:lon],
            existing[:lat], existing[:lon]
          )
          distance < 100 # meters
        end

        deduplicated << result unless duplicate
      end

      deduplicated
    end

    def calculate_distance_in_meters(lat1, lon1, lat2, lon2)
      # Use Geocoder's distance calculation (same as in Distanceable concern)
      distance_km = Geocoder::Calculations.distance_between(
        [lat1, lon1],
        [lat2, lon2],
        units: :km
      )

      # Convert to meters and handle potential nil/invalid results
      return 0 unless distance_km.is_a?(Numeric) && distance_km.finite?

      distance_km * 1000 # Convert km to meters
    end

    def valid_coordinates?(lat, lon)
      lat.between?(-90, 90) && lon.between?(-180, 180)
    end
  end
end
