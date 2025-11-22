# frozen_string_literal: true

# This class uses Komoot's Photon API
class ReverseGeocoding::Places::FetchData
  attr_reader :place

  def initialize(place_id)
    @place = Place.find(place_id)
  end

  def call
    unless DawarichSettings.reverse_geocoding_enabled?
      Rails.logger.warn('Reverse geocoding is not enabled')

      return
    end

    places = geocoder_places
    first_place = places.shift
    update_place(first_place)

    osm_ids = extract_osm_ids(places)

    return if osm_ids.empty?

    existing_places = find_existing_places(osm_ids)

    places_to_create, places_to_update = prepare_places_for_bulk_operations(places, existing_places)

    save_places(places_to_create, places_to_update)
  end

  private

  def update_place(reverse_geocoded_place)
    return if reverse_geocoded_place.nil?

    data = reverse_geocoded_place.data

    place.update!(
      name:       place_name(data),
      lonlat:     build_point_coordinates(data['geometry']['coordinates']),
      city:       data['properties']['city'],
      country:    data['properties']['country'],
      geodata:    data,
      source:     Place.sources[:photon],
      reverse_geocoded_at: Time.current
    )
  end


  def find_place(place_data, existing_places)
    osm_id = place_data['properties']['osm_id'].to_s

    existing_place = existing_places[osm_id]

    return existing_place if existing_place.present?

    coordinates = place_data['geometry']['coordinates']

    Place.new(
      lonlat: build_point_coordinates(coordinates),
      latitude: coordinates[1].to_f.round(5),
      longitude: coordinates[0].to_f.round(5)
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

  def extract_osm_ids(places)
    places.map { |place| place.data['properties']['osm_id'].to_s }
  end

  def find_existing_places(osm_ids)
    Place.where("geodata->'properties'->>'osm_id' IN (?)", osm_ids)
      .global
      .index_by { |p| p.geodata.dig('properties', 'osm_id').to_s }
      .compact
  end

  def prepare_places_for_bulk_operations(places, existing_places)
    places_to_create = []
    places_to_update = []

    places.each do |reverse_geocoded_place|
      data = reverse_geocoded_place.data
      new_place = find_place(data, existing_places)

      populate_place_attributes(new_place, data)

      if new_place.persisted?
        places_to_update << new_place
      else
        places_to_create << new_place
      end
    end

    [places_to_create, places_to_update]
  end

  def populate_place_attributes(place, data)
    place.name = place_name(data)
    place.city = data['properties']['city']
    place.country = data['properties']['country']
    place.geodata = data
    place.source = :photon

    if place.lonlat.blank?
      place.lonlat = build_point_coordinates(data['geometry']['coordinates'])
    end
  end

  def save_places(places_to_create, places_to_update)
    if places_to_create.any?
      place_attributes = places_to_create.map do |place|
        {
          name: place.name,
          latitude: place.latitude,
          longitude: place.longitude,
          lonlat: place.lonlat,
          city: place.city,
          country: place.country,
          geodata: place.geodata,
          source: place.source,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
      Place.insert_all(place_attributes)
    end

    # Individual updates for existing places
    places_to_update.each(&:save!) if places_to_update.any?
  end

  def build_point_coordinates(coordinates)
    "POINT(#{coordinates[0]} #{coordinates[1]})"
  end

  def geocoder_places
    data = Geocoder.search(
      [place.lat, place.lon],
      limit: 10,
      distance_sort: true,
      radius: 1,
      units: :km
    )
  end
end
