# frozen_string_literal: true

module Places
  class NameFetcher
    def initialize(place)
      @place = place
    end

    def call
      result = Geocoding::Search.call(
        user: place.user_id, query: [place.lat, place.lon], units: :km, limit: 1, distance_sort: true
      ).first
      return nil if result.blank?

      properties = Geocoding::ResultNormalizer.call(result)[:properties]
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
          stale_labels = [Place::DEFAULT_NAME, previous_name, nil].uniq - [propagated_name]
          place.visits.where(location_label: stale_labels).update_all(location_label: propagated_name)
        end
        place.carry_name_to_visits(previous_name) unless place.saved_change_to_name?

        place
      end
    rescue *ReverseGeocoding::ProviderErrors::TRANSIENT => e
      Rails.logger.warn("Geocoding provider error in NameFetcher for place #{place.id}: #{e.message}")
      nil
    rescue Geocoding::Cooldown::Active
      # The provider's refusal was reported when it started the cooldown.
      Rails.logger.info("Geocoding skipped in NameFetcher for place #{place.id}: provider is over its limit")
      retry_after_cooldown
      nil
    rescue Geocoder::OverQueryLimitError => e
      Rails.logger.error("Geocoding error in NameFetcher for place #{place.id}: #{e.message}")
      ExceptionReporter.call(e)
      retry_after_cooldown
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

    def retry_after_cooldown
      wait = Geocoding::Cooldown.retry_after(Geocoding::Config.for(place.user_id))
      return unless Geocoding::Cooldown.claim_retry("place_name:#{place.id}", wait)

      Places::NameFetchingJob.set(wait: wait).perform_later(place.id)
    end
  end
end
