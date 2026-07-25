# frozen_string_literal: true

class ReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding
  sidekiq_options retry: 3

  def perform(klass, id, force: false)
    return unless DawarichSettings.reverse_geocoding_enabled?

    rate_limit_for_photon_api

    data_fetcher(klass, id, force).call
  ensure
    release_dedup_key(klass, id)
  end

  private

  def release_dedup_key(klass, id)
    return unless klass == 'Point'

    Sidekiq.redis { |r| r.del(Point.geocode_dedup_key(id)) }
  end

  def data_fetcher(klass, id, force)
    "ReverseGeocoding::#{klass.pluralize.camelize}::FetchData".constantize.new(id, force: force)
  end

  def rate_limit_for_photon_api
    return unless DawarichSettings.photon_enabled?

    sleep 1 if DawarichSettings.photon_uses_komoot_io?
  end
end
