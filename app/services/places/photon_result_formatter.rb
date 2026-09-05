# frozen_string_literal: true

module Places
  # Flattens a geocoder result into the select_place-compatible shape.
  # Name kept for compatibility; extraction is provider-agnostic.
  module PhotonResultFormatter
    module_function

    def call(result, fallback_lat: nil, fallback_lon: nil)
      fields = Geocoding::ResultNormalizer.call(result)
      properties = fields[:properties]
      coordinates = fields[:coords] || [fallback_lon, fallback_lat]

      {
        id: nil,
        name: extract_name(properties),
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
        postcode: properties['postcode'],
        source: 'photon',
        geodata: result.data
      }
    end

    def extract_name(properties)
      properties['name'] ||
        [properties['street'], properties['housenumber']].compact.join(' ').presence ||
        properties['city'] ||
        'Unknown Place'
    end

    private_class_method :extract_name
  end
end
