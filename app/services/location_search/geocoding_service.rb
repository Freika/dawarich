# frozen_string_literal: true

module LocationSearch
  class GeocodingService
    MAX_RESULTS = 5
    CACHE_TTL = 1.hour

    def initialize
      @cache_key_prefix = 'location_search:geocoding'
    end

    def search(query)
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
          name: extract_name(result),
          address: extract_address(result),
          type: extract_type(result),
          provider_data: extract_provider_data(result)
        }

        normalized_results << normalized_result
      end

      # Remove duplicates based on coordinates (within 100m)
      deduplicate_results(normalized_results)
    end

    def valid_result?(result)
      result.present? && 
        result.latitude.present? && 
        result.longitude.present? &&
        result.latitude.to_f.abs <= 90 &&
        result.longitude.to_f.abs <= 180
    end

    def extract_name(result)
      case provider_name.downcase
      when 'photon'
        extract_photon_name(result)
      when 'nominatim'
        extract_nominatim_name(result)
      when 'geoapify'
        extract_geoapify_name(result)
      else
        result.address || result.data&.dig('display_name') || 'Unknown location'
      end
    end

    def extract_address(result)
      case provider_name.downcase
      when 'photon'
        extract_photon_address(result)
      when 'nominatim'
        extract_nominatim_address(result)
      when 'geoapify'
        extract_geoapify_address(result)
      else
        result.address || result.data&.dig('display_name') || ''
      end
    end

    def extract_type(result)
      data = result.data || {}
      
      case provider_name.downcase
      when 'photon'
        data.dig('properties', 'osm_key') || data.dig('properties', 'type') || 'unknown'
      when 'nominatim'
        data['type'] || data['class'] || 'unknown'
      when 'geoapify'
        data.dig('properties', 'datasource', 'sourcename') || data.dig('properties', 'place_type') || 'unknown'
      else
        'unknown'
      end
    end

    def extract_provider_data(result)
      {
        osm_id: result.data&.dig('properties', 'osm_id'),
        osm_type: result.data&.dig('properties', 'osm_type'),
        place_rank: result.data&.dig('place_rank'),
        importance: result.data&.dig('importance')
      }
    end

    # Provider-specific extractors
    def extract_photon_name(result)
      properties = result.data&.dig('properties') || {}
      properties['name'] || properties['street'] || properties['city'] || 'Unknown location'
    end

    def extract_photon_address(result)
      properties = result.data&.dig('properties') || {}
      parts = []
      
      parts << properties['street'] if properties['street'].present?
      parts << properties['housenumber'] if properties['housenumber'].present?
      parts << properties['city'] if properties['city'].present?
      parts << properties['state'] if properties['state'].present?
      parts << properties['country'] if properties['country'].present?
      
      parts.join(', ')
    end

    def extract_nominatim_name(result)
      data = result.data || {}
      data['display_name']&.split(',')&.first || 'Unknown location'
    end

    def extract_nominatim_address(result)
      result.data&.dig('display_name') || ''
    end

    def extract_geoapify_name(result)
      properties = result.data&.dig('properties') || {}
      properties['name'] || properties['street'] || properties['city'] || 'Unknown location'
    end

    def extract_geoapify_address(result)
      properties = result.data&.dig('properties') || {}
      properties['formatted'] || ''
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
      rkm = 6371000 # Earth radius in meters
      
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