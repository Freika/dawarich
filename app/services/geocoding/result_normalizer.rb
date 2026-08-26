# frozen_string_literal: true

module Geocoding
  # Normalizes a Geocoder result from any supported provider (Photon,
  # Geoapify, Nominatim, LocationIQ) into one canonical shape, so consumers
  # such as place search and visit attribution don't need to know each
  # provider's raw response format.
  #
  # Providers return two distinct shapes:
  #   * GeoJSON-like (Photon, Geoapify): data['properties'] + data['geometry']
  #   * Flat (Nominatim, LocationIQ):    data['address'] + data['lat']/data['lon']
  #
  # Returns { properties: Hash, coords: [lon, lat] | nil }; coords is
  # [longitude, latitude] to match the GeoJSON convention consumers expect.
  module ResultNormalizer
    module_function

    def call(result)
      data = result.data
      return { properties: {}, coords: nil } if data.blank?

      data = data.deep_stringify_keys if data.is_a?(Hash)

      if data['properties'].is_a?(Hash)
        from_geojson(data)
      elsif data['address'].is_a?(Hash) || data['lat'].present? || data['display_name'].present?
        from_flat(data)
      else
        { properties: {}, coords: nil }
      end
    end

    def from_geojson(data)
      properties = data['properties']
      coords = data.dig('geometry', 'coordinates')
      # Geoapify puts coordinates in properties; fall back only when present.
      if coords.blank? && properties['lon'].present? && properties['lat'].present?
        coords = [properties['lon'].to_f, properties['lat'].to_f]
      end

      {
        properties: {
          'name' => properties['name'],
          'street' => properties['street'],
          'housenumber' => properties['housenumber'],
          'city' => properties['city'],
          'country' => properties['country'],
          'postcode' => properties['postcode'],
          'osm_id' => properties['osm_id'],
          'osm_type' => properties['osm_type'],
          'osm_key' => properties['osm_key'] || properties['category'],
          'osm_value' => properties['osm_value'] || properties['result_type'] || properties['type']
        },
        coords: coords
      }
    end

    def from_flat(data)
      address = data['address'] || {}
      coords = [data['lon'].to_f, data['lat'].to_f] if data['lon'].present? && data['lat'].present?

      {
        properties: {
          'name' => data['name'],
          'street' => address['road'] || address['pedestrian'] || address['footway'],
          'housenumber' => address['house_number'],
          'city' => address['city'] || address['town'] || address['village'] || address['municipality'],
          'country' => address['country'],
          'postcode' => address['postcode'],
          'osm_id' => data['osm_id'],
          'osm_type' => data['osm_type'],
          'osm_key' => data['category'],
          'osm_value' => data['type'] || data['addresstype']
        },
        coords: coords
      }
    end

    private_class_method :from_geojson, :from_flat
  end
end
