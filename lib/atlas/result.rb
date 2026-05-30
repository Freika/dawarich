# frozen_string_literal: true

module Atlas
  # Wraps a single Atlas result row into the small, gem-compatible interface
  # the rest of the app relies on (`#city`, `#country`, `#data`,
  # `#coordinates`, ...). Mirrors Geocoder::Result so Atlas results are a
  # drop-in for the data the geocoder gem used to return.
  class Result
    def initialize(data)
      @data = data || {}
    end

    attr_reader :data

    def coordinates
      [latitude, longitude]
    end

    def latitude
      fetch_coordinate(:lat, 'lat', 0)
    end

    def longitude
      fetch_coordinate(:lon, 'lon', 1)
    end

    def city
      address['city'] || address['town'] || address['village'] || address['municipality']
    end

    def country
      address['country']
    end

    def country_code
      address['country_code']
    end

    def address
      data['address'] || data.dig('properties', 'address') || data.fetch('properties', {}) || {}
    end

    def display_name
      data['display_name'] || data.dig('properties', 'name') || data['name']
    end

    def name
      data['name'] || data.dig('properties', 'name')
    end

    private

    def fetch_coordinate(coord_key, string_key, array_index)
      return data[coord_key] if data[coord_key]
      return data[string_key] if data[string_key]

      geometry = data['geometry'] || data.dig('properties', 'geometry')
      return geometry['coordinates'][array_index] if geometry&.dig('coordinates')

      nil
    end
  end
end
