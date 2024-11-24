# frozen_string_literal: true

class ReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform(klass, id)
    return unless REVERSE_GEOCODING_ENABLED

    rate_limit_for_photon_api

    data_fetcher(klass, id).call
  end

  private

  def data_fetcher(klass, id)
    "ReverseGeocoding::#{klass.pluralize.camelize}::FetchData".constantize.new(id)
  end

  def rate_limit_for_photon_api
    return unless PHOTON_API_HOST == 'photon.komoot.io'

    sleep 1 if PHOTON_API_HOST == 'photon.komoot.io'
  end
end
