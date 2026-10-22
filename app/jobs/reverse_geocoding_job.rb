# frozen_string_literal: true

class ReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding
  sidekiq_options retry: 3

  sidekiq_retries_exhausted do |job, _error|
    klass, id, options = job.fetch('args').first.fetch('arguments')
    release_geocode_claim(klass, id, force: options&.fetch('force', false))
  end

  def perform(klass, id, force: false)
    record = klass.to_s.classify.constantize.find_by(id: id)
    return if record.nil?

    config = Geocoding::Config.for(record.user_id)
    return unless config.enabled?

    # Pacing lives in Geocoding::RateLimiter, one layer down: sleeping here
    # only spaced out a single thread while the rest of the pool kept firing.
    data_fetcher(klass, id, force).call
  rescue StandardError
    retrying = true
    raise
  ensure
    self.class.release_geocode_claim(klass, id, force: force) unless retrying
  end

  def self.release_geocode_claim(klass, id, force: false)
    return unless klass == 'Point'
    return if force

    Sidekiq.redis { |r| r.del(Point.geocode_dedup_key(id)) }
  rescue StandardError => e
    Rails.logger.warn("Failed to release geocode dedup key for point #{id}: #{e.message}")
  end

  private

  def data_fetcher(klass, id, force)
    "ReverseGeocoding::#{klass.pluralize.camelize}::FetchData".constantize.new(id, force: force)
  end
end
