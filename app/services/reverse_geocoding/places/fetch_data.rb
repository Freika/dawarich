# frozen_string_literal: true

class ReverseGeocoding::Places::FetchData
  attr_reader :place

  def initialize(place_id)
    @place = Place.find(place_id)
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error("Place with id #{place_id} not found: #{e.message}")
  end

  def call
    return if place.reverse_geocoded?

    if ENV['GOOGLE_PLACES_API_KEY'].blank?
      Rails.logger.warn('GOOGLE_PLACES_API_KEY is not set')

      return
    end

    data             = Geocoder.search([place.latitude, place.longitude])
    google_place_ids = data.map { _1.data['place_id'] }
    first_place      = google_places_client.spot(google_place_ids.shift)

    update_place(first_place)
    google_place_ids.each { |google_place_id| fetch_and_create_place(google_place_id) }
  end

  private

  def google_places_client
    @google_places_client ||= GooglePlaces::Client.new(ENV['GOOGLE_PLACES_API_KEY'])
  end

  def update_place(place)
    place.update!(
      name:       place.name,
      latitude:   place.lat,
      longitude:  place.lng,
      city:       place.city,
      country:    place.country,
      raw_data:   place.raw_data,
      source:     :google_places,
      reverse_geocoded_at: Time.zone.now
    )
  end

  def fetch_and_create_place(place_id)
    place_data = google_places_client.spot(place_id)

    Place.create!(
      name:      place_data.name,
      latitude:  place_data.lat,
      longitude: place_data.lng,
      city:      place_data.city,
      country:   place_data.country,
      raw_data:  place_data.raw_data,
      source:    :google_places
    )
  end

  def reverse_geocoded?
    place.geodata.present?
  end
end
