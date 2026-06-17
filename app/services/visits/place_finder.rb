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

      existing = find_existing_place(lat, lon, visit_data[:suggested_name])
      return existing if existing

      create_default_place(lat, lon, visit_data[:suggested_name])
    end

    private

    def find_existing_place(lat, lon, name)
      return ranked_existing_place(lat, lon, name) if ranked?

      by_location = user.places.near([lat, lon], SIMILARITY_RADIUS, :m).first
      return by_location if by_location

      return nil if name.blank?

      user.places.where(name: name).near([lat, lon], SIMILARITY_RADIUS * 2, :m).first
    end

    # Flag-on: rank candidates within the radius by exact-name, then manual-over-photon, then distance.
    # Avoids minting duplicate "Suggested place" rows and prefers user-curated places.
    def ranked_existing_place(lat, lon, name)
      candidates = user.places.near([lat, lon], SIMILARITY_RADIUS, :m).to_a
      return nil if candidates.empty?

      candidates.min_by do |place|
        [
          name.present? && place.name == name ? 0 : 1,
          place.manual? ? 0 : 1,
          distance_meters(lat, lon, place.lat, place.lon)
        ]
      end
    end

    def distance_meters(lat, lon, other_lat, other_lon)
      Geocoder::Calculations.distance_between([lat, lon], [other_lat, other_lon], units: :km) * 1000
    end

    def ranked?
      return @ranked if defined?(@ranked)

      @ranked =
        begin
          Flipper.enabled?(:stay_point_detection, user)
        rescue StandardError => e
          Rails.logger.warn("[Visits::PlaceFinder] Flipper unavailable, unranked lookup: #{e.class}: #{e.message}")
          false
        end
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
