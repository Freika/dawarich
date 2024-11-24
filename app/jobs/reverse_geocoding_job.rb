# frozen_string_literal: true

class ReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding

  def perform(klass, id)
    return unless REVERSE_GEOCODING_ENABLED

    sleep 1 if PHOTON_API_HOST == 'photon.komoot.io'

    data_fetcher(klass, id).call
  end

  private

  def data_fetcher(klass, id)
    "ReverseGeocoding::#{klass.pluralize.camelize}::FetchData".constantize.new(id)
  end
end
