# frozen_string_literal: true

module Dawarich
  module ReverseGeocodingLimits
    QUEUE = 'reverse_geocoding'

    def self.limit(rps:, override:)
      value = override || rps&.ceil
      value && [value, 1].max
    end

    def self.process_limit(pool)
      [pool - 1, 1].max
    end

    def self.configure!(config)
      limits = { limit: current_limit, process_limit: process_limit(config.concurrency) }
      config[:limits] = config[:limits].to_h.merge(QUEUE => limits[:limit])
      config[:process_limits] = config[:process_limits].to_h.merge(QUEUE => limits[:process_limit])
      Rails.logger.info(
        "[ReverseGeocodingLimits] limit=#{limits[:limit] || 'none'} process_limit=#{limits[:process_limit]}"
      )
    end

    def self.refresh!
      Sidekiq::Queue[QUEUE].limit = current_limit
    end

    def self.current_limit
      limit(rps: provider_rps, override: ENV['REVERSE_GEOCODING_CONCURRENCY'].presence&.to_i)
    end

    def self.provider_rps
      Geocoding::Config.for.rps
    rescue StandardError => e
      Rails.logger.warn("[ReverseGeocodingLimits] geocoding config unavailable: #{e.class}: #{e.message}")
      nil
    end

    private_class_method :current_limit, :provider_rps
  end
end
