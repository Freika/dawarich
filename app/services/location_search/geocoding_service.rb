# frozen_string_literal: true

module LocationSearch
  class GeocodingService
    MAX_RESULTS = 10
    CACHE_TTL = 1.hour

    def initialize(query)
      @query = query
      @cache_key_prefix = 'location_search:geocoding'
    end

    def search
      return [] if query.blank?

      cache_key = "#{@cache_key_prefix}:#{Digest::SHA256.hexdigest(query.downcase)}"

      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) do
        perform_geocoding_search(query)
      end
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
      normalized_results = []

      results.each do |result|
        next unless valid_result?(result)

        normalized_result = {
          lat: result.latitude.to_f,
          lon: result.longitude.to_f,
          name: result.address&.split(',')&.first || 'Unknown location',
          address: result.address || '',
          type: result.data&.dig('type') || result.data&.dig('class') || 'unknown',
          provider_data: {
            osm_id: result.data&.dig('osm_id'),
            place_rank: result.data&.dig('place_rank'),
            importance: result.data&.dig('importance')
          }
        }

        normalized_results << normalized_result
      end

      deduplicate_results(normalized_results)
    end

    def valid_result?(result)
      result.present? &&
        result.latitude.present? &&
        result.longitude.present? &&
        result.latitude.to_f.abs <= 90 &&
        result.longitude.to_f.abs <= 180
    end


    def deduplicate_results(results)
      deduplicated = []

      results.each do |result|
        # Check if there's already a result within 100m
        duplicate = deduplicated.find do |existing|
          distance = calculate_distance(
            result[:lat], result[:lon],
            existing[:lat], existing[:lon]
          )
          distance < 100 # meters
        end

        deduplicated << result unless duplicate
      end

      deduplicated
    end

    def calculate_distance(lat1, lon1, lat2, lon2)
      # Haversine formula for distance calculation in meters
      rad_per_deg = Math::PI / 180
      rkm = 6_371_000 # Earth radius in meters

      dlat_rad = (lat2 - lat1) * rad_per_deg
      dlon_rad = (lon2 - lon1) * rad_per_deg

      lat1_rad = lat1 * rad_per_deg
      lat2_rad = lat2 * rad_per_deg

      a = Math.sin(dlat_rad / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon_rad / 2)**2
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

      rkm * c
    end

  end
end
