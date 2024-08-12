# frozen_string_literal: true

class ReverseGeocoding::Places::FetchData
  attr_reader :place

  def initialize(place_id)
    @place = Place.find(place_id)
  end

  def call
    if GOOGLE_PLACES_API_KEY.blank?
      Rails.logger.warn('GOOGLE_PLACES_API_KEY is not set')

      return
    end

    # return if place.reverse_geocoded?

    google_places = google_places_client.spots(place.latitude, place.longitude, radius: 10)
    first_place = google_places.shift
    update_place(first_place)
    add_suggested_place_to_a_visit
    google_places.each { |google_place| fetch_and_create_place(google_place) }
  end

  private

  def google_places_client
    @google_places_client ||= GooglePlaces::Client.new(GOOGLE_PLACES_API_KEY)
  end

  def update_place(google_place)
    place.update!(
      name:       google_place.name,
      latitude:   google_place.lat,
      longitude:  google_place.lng,
      city:       google_place.city,
      country:    google_place.country,
      geodata:    google_place.json_result_object,
      source:     :google_places,
      reverse_geocoded_at: Time.current
    )
  end

  def fetch_and_create_place(google_place)
    new_place = find_google_place(google_place)

    new_place.name = google_place.name
    new_place.city = google_place.city
    new_place.country = google_place.country
    new_place.geodata = google_place.json_result_object
    new_place.source = :google_places

    new_place.save!

    add_suggested_place_to_a_visit(suggested_place: new_place)
  end

  def reverse_geocoded?
    place.geodata.present?
  end

  def add_suggested_place_to_a_visit(suggested_place: place)
    # 1. Find all visits that are close to the place
    # 2. Add the place to the visit as a suggestion
    visits = Place.near([suggested_place.latitude, suggested_place.longitude], 0.1).flat_map(&:visits)

    # This is a very naive implementation, we should probably check if the place is already suggested
    visits.each { |visit| visit.suggested_places << suggested_place }
  end

  def find_google_place(google_place)
    place = Place.where("geodata ->> 'place_id' = ?", google_place['place_id']).first

    return place if place.present?

    Place.find_or_initialize_by(
      latitude: google_place['geometry']['location']['lat'],
      longitude: google_place['geometry']['location']['lng']
    )
  end
end
