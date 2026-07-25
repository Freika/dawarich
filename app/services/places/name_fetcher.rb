# frozen_string_literal: true

module Places
  class NameFetcher
    def self.lookup_attrs(lat, lon)
      return nil unless DawarichSettings.reverse_geocoding_enabled?

      result = Geocoder.search([lat, lon], units: :km, limit: 1, distance_sort: true).first
      return nil if result.blank?

      properties = result.data&.dig('properties')
      return nil if properties.blank?

      name = ::Visits::Names::Builder.build_from_properties(properties)

      { name: name, city: properties['city'], country: properties['country'], geodata: result.data }
    rescue StandardError => e
      ExceptionReporter.call(e, "NameFetcher.lookup_attrs failed for #{lat},#{lon}")
      nil
    end

    def initialize(place)
      @place = place
    end

    def call
      result = Geocoder.search([place.lat, place.lon], units: :km, limit: 1, distance_sort: true).first
      return nil if result.blank?

      properties = result.data&.dig('properties')
      return nil if properties.blank?

      name = ::Visits::Names::Builder.build_from_properties(properties)

      ActiveRecord::Base.transaction do
        place.name = name if name.present?
        place.city = properties['city'] if properties['city'].present?
        place.country = properties['country'] if properties['country'].present?
        place.geodata = result.data if DawarichSettings.store_geodata?
        place.save!
        place.visits.where(name: Place::DEFAULT_NAME).update_all(name: name) if name.present?
        place
      end
    rescue *ReverseGeocoding::ProviderErrors::TRANSIENT => e
      Rails.logger.warn("Geocoding provider error in NameFetcher for place #{place.id}: #{e.message}")
      nil
    rescue StandardError => e
      if ReverseGeocoding::ProviderErrors.transient_tls?(e)
        Rails.logger.warn("Geocoding provider error in NameFetcher for place #{place.id}: #{e.message}")
      else
        Rails.logger.error("Geocoding error in NameFetcher for place #{place.id}: #{e.message}")
        ExceptionReporter.call(e)
      end
      nil
    end

    private

    attr_reader :place
  end
end
