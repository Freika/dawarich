# frozen_string_literal: true

module Places
  class NameFetcher
    def initialize(place)
      @place = place
    end

    def call
      geodata = Geocoder.search([place.lat, place.lon], units: :km, limit: 1, distance_sort: true).first

      return if geodata.blank?

      properties = geodata.data&.dig('properties')
      return if properties.blank?

      ActiveRecord::Base.transaction do
        update_place_name(properties, geodata)

        update_visits_name(properties) if properties['name'].present?

        place
      end
    end

    private

    attr_reader :place

    def update_place_name(properties, geodata)
      place.name = properties['name'] if properties['name'].present?
      place.city = properties['city'] if properties['city'].present?
      place.country = properties['country'] if properties['country'].present?
      place.geodata = geodata.data if DawarichSettings.store_geodata?

      place.save!
    end

    def update_visits_name(properties)
      place.visits.where(name: Place::DEFAULT_NAME).update_all(name: properties['name'])
    end
  end
end
