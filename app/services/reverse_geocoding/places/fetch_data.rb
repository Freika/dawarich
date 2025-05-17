# frozen_string_literal: true

# This class uses Komoot's Photon API
class ReverseGeocoding::Places::FetchData
  attr_reader :place

  IGNORED_OSM_VALUES = %w[house residential yes detached].freeze
  IGNORED_OSM_KEYS = %w[highway railway].freeze

  def initialize(place_id)
    @place = Place.find(place_id)
  end

  def call
    unless DawarichSettings.reverse_geocoding_enabled?
      Rails.logger.warn('Reverse geocoding is not enabled')
      return
    end

    places = reverse_geocoded_places
    first_place = places.shift
    update_place(first_place)

    osm_ids = places.map { |place| place.data['properties']['osm_id'].to_s }

    return if osm_ids.empty?

    existing_places =
      Place.where("geodata->'properties'->>'osm_id' IN (?)", osm_ids)
        .index_by { |p| p.geodata.dig('properties', 'osm_id').to_s }
        .compact

    places.each do |reverse_geocoded_place|
      fetch_and_create_place(reverse_geocoded_place, existing_places)
    end
  end

  private

  def update_place(reverse_geocoded_place)
    return if reverse_geocoded_place.nil?

    data = reverse_geocoded_place.data

    place.update!(
      name:       place_name(data),
      lonlat:     "POINT(#{data['geometry']['coordinates'][0]} #{data['geometry']['coordinates'][1]})",
      city:       data['properties']['city'],
      country:    data['properties']['country'],
      geodata:    data,
      source:     Place.sources[:photon],
      reverse_geocoded_at: Time.current
    )
  end

  def fetch_and_create_place(reverse_geocoded_place, existing_places)
    data = reverse_geocoded_place.data
    new_place = find_place(data, existing_places)

    new_place.name = place_name(data)
    new_place.city = data['properties']['city']
    new_place.country = data['properties']['country'] # TODO: Use country id
    new_place.geodata = data
    new_place.source = :photon
    if new_place.lonlat.blank?
      new_place.lonlat = "POINT(#{data['geometry']['coordinates'][0]} #{data['geometry']['coordinates'][1]})"
    end

    new_place.save!
  end

  def find_place(place_data, existing_places)
    osm_id = place_data['properties']['osm_id'].to_s

    existing_place = existing_places[osm_id]
    return existing_place if existing_place.present?

    # If not found in existing places, initialize a new one
    Place.new(
      lonlat: "POINT(#{place_data['geometry']['coordinates'][0].to_f.round(5)} #{place_data['geometry']['coordinates'][1].to_f.round(5)})",
      latitude: place_data['geometry']['coordinates'][1].to_f.round(5),
      longitude: place_data['geometry']['coordinates'][0].to_f.round(5)
    )
  end

  def place_name(data)
    name = data.dig('properties', 'name')
    type = data.dig('properties', 'osm_value')&.capitalize&.gsub('_', ' ')
    address = "#{data.dig('properties', 'postcode')} #{data.dig('properties', 'street')}"
    address += " #{data.dig('properties', 'housenumber')}" if data.dig('properties', 'housenumber').present?

    name ||= address

    "#{name} (#{type})"
  end

  def reverse_geocoded_places
    data = Geocoder.search(
      [place.lat, place.lon],
      limit: 10,
      distance_sort: true,
      radius: 1,
      units: ::DISTANCE_UNIT
    )

    data.reject do |place|
      place.data['properties']['osm_value'].in?(IGNORED_OSM_VALUES) ||
        place.data['properties']['osm_key'].in?(IGNORED_OSM_KEYS)
    end
  end
end
