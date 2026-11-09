# frozen_string_literal: true

class ReverseGeocodingJob < ApplicationJob
  queue_as :reverse_geocoding
  sidekiq_options retry: 3

  # Queued payloads carry the type as a string ('Point', 'place').
  RECORD_TYPES = {
    'point' => ['Point', 'ReverseGeocoding::Points::FetchData'],
    'place' => ['Place', 'ReverseGeocoding::Places::FetchData']
  }.freeze

  sidekiq_retries_exhausted do |job, _error|
    klass, id, options = job.fetch('args').first.fetch('arguments')
    release_geocode_claim(klass, id, force: options&.fetch('force', false))
  end

  def perform(klass, id, force: false)
    model, fetcher = self.class.record_type(klass).map(&:constantize)
    record = model.find_by(id: id)
    return if record.nil?

    config = Geocoding::Config.for(record.user_id)
    return unless config.enabled?

    # Pacing lives in Geocoding::RateLimiter, one layer down: sleeping here
    # only spaced out a single thread while the rest of the pool kept firing.
    fetcher.new(id, force: force).call
  rescue StandardError
    retrying = true
    raise
  ensure
    self.class.release_geocode_claim(klass, id, force: force) unless retrying
  end

  def self.record_type(klass)
    RECORD_TYPES.fetch(klass.to_s.downcase) do
      raise ArgumentError, "#{klass} records are not reverse geocoded"
    end
  end

  def self.release_geocode_claim(klass, id, force: false)
    return unless klass.to_s.casecmp?('Point')
    return if force

    Sidekiq.redis { |r| r.del(Point.geocode_dedup_key(id)) }
  rescue StandardError => e
    Rails.logger.warn("Failed to release geocode dedup key for point #{id}: #{e.message}")
  end
end
