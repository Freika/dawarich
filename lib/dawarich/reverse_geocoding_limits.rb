# frozen_string_literal: true

module Dawarich
  module ReverseGeocodingLimits
    QUEUE = 'reverse_geocoding'

    def self.for(pool:, rps:, override:)
      limit = override || rps&.ceil
      { limit: limit && [limit, 1].max, process_limit: [pool - 1, 1].max }
    end

    def self.configure!(config, override:)
      limits = self.for(pool: config.concurrency, rps: provider_rps, override: override)
      config[:limits] = config[:limits].to_h.merge(QUEUE => limits[:limit])
      config[:process_limits] = config[:process_limits].to_h.merge(QUEUE => limits[:process_limit])
    end

    def self.provider_rps
      Geocoding::Config.for.rps
    rescue StandardError => e
      Rails.logger.warn("[ReverseGeocodingLimits] geocoding config unavailable: #{e.class}: #{e.message}")
      nil
    end

    private_class_method :provider_rps
  end
end
