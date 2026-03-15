# frozen_string_literal: true

module Places
  class NearbySearch
    RADIUS_KM = 0.5
    MAX_RESULTS = 10

    def initialize(latitude:, longitude:, radius: RADIUS_KM, limit: MAX_RESULTS)
      @latitude = latitude
      @longitude = longitude
      @radius = radius
      @limit = limit
    end

    def call
      return [] unless reverse_geocoding_enabled?

      results = Geocoder.search(
        [latitude, longitude],
        limit: limit,
        distance_sort: true,
        radius: radius,
        units: :km
      )

      format_results(results)
    rescue StandardError => e
      Rails.logger.error("Nearby places search error: #{e.message}")
      []
    end

    private

    attr_reader :latitude, :longitude, :radius, :limit

    def reverse_geocoding_enabled?
      DawarichSettings.reverse_geocoding_enabled?
    end

    def format_results(results)
      results.map do |result|
        properties = result.data['properties'] || {}
        coordinates = result.data.dig('geometry', 'coordinates') || [longitude, latitude]

        {
          name: extract_name(result.data),
          latitude: coordinates[1],
          longitude: coordinates[0],
          osm_id: properties['osm_id'],
          osm_type: properties['osm_type'],
          osm_key: properties['osm_key'],
          osm_value: properties['osm_value'],
          city: properties['city'],
          country: properties['country'],
          street: properties['street'],
          housenumber: properties['housenumber'],
          postcode: properties['postcode']
        }
      end
    end

    def extract_name(data)
      properties = data['properties'] || {}

      properties['name'] ||
        [properties['street'], properties['housenumber']].compact.join(' ').presence ||
        properties['city'] ||
        'Unknown Place'
    end
  end
end
