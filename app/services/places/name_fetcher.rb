# frozen_string_literal: true

module Places
  class NameFetcher
    def initialize(place)
      @place = place
    end

    def call
      result = Geocoding::Search.call(
        user: place.user_id,
        query: [place.lat, place.lon],
        timeout: REVERSE_GEOCODING_TIMEOUT,
        units: :km,
        limit: 1,
        distance_sort: true
      ).first
      return nil if result.blank?

      properties = result.data&.dig('properties')
      return nil if properties.blank?

      name = ::Visits::Names::Builder.build_from_properties(properties)

      ActiveRecord::Base.transaction do
        previous_name = place.name
        place.machine_named = true
        place.name = name if name.present? && !place.name_locked?
        place.city = properties['city'] if properties['city'].present?
        place.country = properties['country'] if properties['country'].present?
        place.geodata = result.data if DawarichSettings.store_geodata?
        place.save!

        propagated_name = place.name
        if propagated_name.present?
          stale_names = [Place::DEFAULT_NAME, previous_name].uniq - [propagated_name]
          place.visits.where(name: stale_names).update_all(name: propagated_name) if stale_names.any?
        end

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
