# frozen_string_literal: true

module Visits
  class PlaceFinder
    SIMILARITY_RADIUS = 50

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def find_or_create_place(visit_data)
      lat = visit_data[:center_lat]
      lon = visit_data[:center_lon]

      existing = find_existing_place(lat, lon, visit_data[:suggested_name], visit_data[:external_place_id])
      return existing if existing

      create_default_place(lat, lon, visit_data[:suggested_name])
    end

    private

    def find_existing_place(lat, lon, name, external_place_id)
      external = place_by_external_id(external_place_id)
      return external if external

      normalized_name = (name.presence || Place::DEFAULT_NAME).strip.downcase
      candidates = user.places
                       .where('LOWER(BTRIM(name)) = ?', normalized_name)
                       .near([lat, lon], SIMILARITY_RADIUS, :m)
                       .to_a
      return nil if candidates.empty?

      candidates.min_by { |place| [distance_meters(lat, lon, place.lat, place.lon), place.id] }
    end

    def place_by_external_id(external_place_id)
      return if external_place_id.blank?

      user.places.find_by("geodata ->> 'external_place_id' = ?", external_place_id.to_s)
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

      Places::NameFetchingJob.perform_later(place.id) if Geocoding::Config.for(user).enabled?
      place
    end
  end
end
