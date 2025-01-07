# frozen_string_literal: true

class ReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform(klass, id)
    return unless DawarichSettings.reverse_geocoding_enabled?

    rate_limit_for_photon_api

    data_fetcher(klass, id).call
  end

  private

  def data_fetcher(klass, id)
    "ReverseGeocoding::#{klass.pluralize.camelize}::FetchData".constantize.new(id)
  end

  def rate_limit_for_photon_api
    return unless DawarichSettings.photon_enabled?

    sleep 1 if DawarichSettings.photon_uses_komoot_io?
  end
end
