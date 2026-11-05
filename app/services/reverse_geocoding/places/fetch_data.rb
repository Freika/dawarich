# frozen_string_literal: true

class ReverseGeocoding::Places::FetchData
  attr_reader :place

  def initialize(place_id, force: false) # rubocop:disable Lint/UnusedMethodArgument
    @place = Place.find(place_id)
  end

  def call
    unless Geocoding::Config.for(place.user_id).enabled?
      Rails.logger.warn('Reverse geocoding is not enabled')

      return
    end

    # Only the nearest feature is used. Other nearby features are not saved as
    # places: they had no visit, so they cluttered the Places list and Possible
    # Duplicates, and came back after every merge. The visit place picker
    # (Places::NearbySearch) fetches its candidates live.
    update_place(geocoder_places.first)
  end

  private

  def update_place(reverse_geocoded_place)
    return if reverse_geocoded_place.nil?

    data = normalize_geocoder_data(reverse_geocoded_place.data)

    attributes = {
      lonlat:     build_point_coordinates(data['geometry']['coordinates']),
      city:       data['properties']['city'],
      country:    data['properties']['country'],
      geodata:    geodata_for(place, data),
      reverse_geocoded_at: Time.current
    }

    unless place.name_locked?
      attributes[:name] = place_name(data)
      attributes[:source] = :photon unless place.gpx_waypoint?
    end

    place.machine_named = true
    place.update!(attributes)
  end

  def place_name(data)
    name = meaningful_place_name(data.dig('properties', 'name'))
    type = formatted_place_type(data.dig('properties', 'osm_value'))
    address = "#{data.dig('properties', 'postcode')} #{data.dig('properties', 'street')}".strip
    address += " #{data.dig('properties', 'housenumber')}" if data.dig('properties', 'housenumber').present?

    name ||= address.presence || Place::DEFAULT_NAME

    return name if type.blank?

    "#{name} (#{type})"
  end

  def meaningful_place_name(value)
    normalized = value.to_s.strip
    return nil if generic_osm_value?(normalized)

    normalized.presence
  end

  def formatted_place_type(value)
    normalized = value.to_s.strip
    return nil if generic_osm_value?(normalized)

    normalized.capitalize.gsub('_', ' ').presence
  end

  def generic_osm_value?(value)
    value.blank? || %w[yes no].include?(value.downcase)
  end

  # Written by the enhanced-import writers and keyed on by find_by_external_id
  # and the partial unique index; a reverse-geocode must never erase them.
  IDENTITY_KEYS = %w[external_place_id semantic_type].freeze
  # The only provider properties this app reads back: the possible_places
  # payload exposes all four, and matches the visit's current place against
  # the live suggestions on osm_id. They are kept even when the operator opted
  # out of storing geodata, because dropping them would break that dedup
  # rather than protect privacy.
  INDEXED_PROPERTY_KEYS = %w[osm_id osm_type osm_key osm_value].freeze

  def geodata_for(place, data)
    identity = (place.geodata || {}).slice(*IDENTITY_KEYS)
    return data.merge(identity) if DawarichSettings.store_geodata?

    identity.merge('properties' => (data['properties'] || {}).slice(*INDEXED_PROPERTY_KEYS).compact)
  end

  def build_point_coordinates(coordinates)
    "POINT(#{coordinates[0]} #{coordinates[1]})"
  end

  def geocoder_places
    Geocoding::Search.call(
      user: place.user_id,
      query: [place.lat, place.lon],
      limit: 1,
      distance_sort: true,
      radius: 1,
      units: :km
    )
  rescue StandardError => e
    Rails.logger.error("Reverse geocoding error for place #{place.id}: #{e.message}")
    ExceptionReporter.call(e)
    []
  end

  # Keep existing GeoJSON metadata intact. Flat responses use the shared
  # field extraction, with this service's legacy address-label naming policy.
  def normalize_geocoder_data(data)
    return data if data.key?('geometry')

    fields = Geocoding::ResultNormalizer.from_data(data)
    properties = fields[:properties]

    {
      'geometry' => { 'coordinates' => fields[:coords] },
      'properties' => properties.merge('name' => properties['address_name'] || properties['name'])
    }
  end
end
