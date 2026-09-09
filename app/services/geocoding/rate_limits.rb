# frozen_string_literal: true

module Geocoding
  # Requests-per-second ceilings for forward and reverse geocoding lookups.
  #
  # Komoot publishes a hard 1 req/s limit for its public Photon instance, so
  # that rate is fixed rather than a user preference. ChibiGeo meters per plan
  # (Hobby 1, Self-Hoster 5, Builder 10, Scale 25) and Dawarich cannot tell
  # which plan a key belongs to, so it starts at the free tier and clamps to
  # the fastest plan a user can buy - asking for more only earns a 429, which
  # the fetchers swallow as a silently skipped geocode. Every other host is one
  # Dawarich knows nothing about, so it stays unlimited unless the user says
  # otherwise.
  module RateLimits
    KOMOOT_RPS = 1.0
    CHIBIGEO_DEFAULT_RPS = 1.0
    CHIBIGEO_MIN_RPS = 1.0
    CHIBIGEO_MAX_RPS = 25.0
    CUSTOM_MIN = 0.1
    CUSTOM_MAX = 1000.0

    Rule = Data.define(:locked, :default, :min, :max) do
      def normalize(value)
        return default if locked

        number = to_number(value)
        return default if number.nil? || number <= 0

        number.clamp(min, max)
      end

      private

      def to_number(value)
        return value.to_f if value.is_a?(Numeric)

        string = value.to_s.strip
        return nil if string.empty?

        Float(string)
      rescue ArgumentError, TypeError
        nil
      end
    end

    def self.for(provider, host)
      if Providers.komoot?(provider, host)
        Rule.new(locked: true, default: KOMOOT_RPS, min: KOMOOT_RPS, max: KOMOOT_RPS)
      elsif Providers.chibigeo?(provider, host)
        Rule.new(locked: false, default: CHIBIGEO_DEFAULT_RPS, min: CHIBIGEO_MIN_RPS, max: CHIBIGEO_MAX_RPS)
      else
        Rule.new(locked: false, default: nil, min: CUSTOM_MIN, max: CUSTOM_MAX)
      end
    end
  end
end
