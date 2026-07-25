# frozen_string_literal: true

module Visits
  class PlaceFinder
    SIMILARITY_RADIUS = 50
    MANUAL_MATCH_RADIUS = 100

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def find_or_create_place(visit_data)
      lat = visit_data[:center_lat]
      lon = visit_data[:center_lon]

      existing = find_existing_place(lat, lon, visit_data[:suggested_name])
      return existing if existing

      create_default_place(lat, lon, visit_data[:suggested_name])
    end

    private

    # Prefer a user-named place over a reverse-geocoded one, then exact-name, then distance.
    # Manual places are matched within a wider radius so a re-visit whose cluster center
    # drifted still reuses the curated place instead of minting a new "Suggested place".
    def find_existing_place(lat, lon, name)
      candidates = user.places.near([lat, lon], MANUAL_MATCH_RADIUS, :m).to_a
      manual = candidates.select(&:manual?)
      pool = manual.presence || candidates.select do |place|
        distance_meters(lat, lon, place.lat, place.lon) <= SIMILARITY_RADIUS
      end
      return nil if pool.empty?

      pool.min_by do |place|
        [
          place.manual? ? 0 : 1,
          name.present? && place.name == name ? 0 : 1,
          distance_meters(lat, lon, place.lat, place.lon)
        ]
      end
    end

    def distance_meters(lat, lon, other_lat, other_lon)
      Geocoder::Calculations.distance_between([lat, lon], [other_lat, other_lon], units: :km) * 1000
    end

    def create_default_place(lat, lon, suggested_name)
      place = user.places.create!(
        name:      suggested_name.presence || Place::DEFAULT_NAME,
        geodata:   {},
        latitude:  lat,
        longitude: lon,
        lonlat:    "POINT(#{lon} #{lat})",
        source:    :photon
      )

      Places::NameFetchingJob.perform_later(place.id) if DawarichSettings.reverse_geocoding_enabled?
      place
    end
  end
end
