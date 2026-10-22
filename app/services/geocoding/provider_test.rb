# frozen_string_literal: true

module Geocoding
  # Runs one reverse lookup against the provider the instance resolves to, and
  # answers with a flash type and a message an admin can act on.
  class ProviderTest
    TEST_COORDINATES = [51.3402, 12.3712].freeze
    MAX_WAIT = 5.0
    # Network and provider failures whose message is safe to show; anything
    # else is reported by class name only, so internals never reach the page.
    SAFE_ERRORS = [
      SocketError, Resolv::ResolvError, Timeout::Error, OpenSSL::SSL::SSLError,
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
      Geocoder::Error
    ].freeze

    def self.call(config = Config.resolved_config)
      new(config).call
    end

    def initialize(config)
      @config = config
    end

    def call
      return [:alert, message(:not_configured)] unless config.enabled?

      results = Search.with_config(config: config, query: TEST_COORDINATES, limit: 1, max_wait: MAX_WAIT)
      return [:alert, message(:rate_limited)] if results.nil?

      result = results.first
      return [:alert, message(:empty)] unless result

      place = [result.city, result.country].compact_blank.join(', ')
      [:notice, message(:success, place: place.presence || result.address)]
    rescue StandardError => e
      Rails.logger.error("Geocoding provider test failed: #{e.class}: #{e.message}")
      [:alert, message(:failure, error: describe(e))]
    end

    private

    attr_reader :config

    def message(key, **interpolations)
      I18n.t("admin.settings.test_geocoding.#{key}", **interpolations)
    end

    def describe(error)
      return "#{error.class}: #{error.message}" if SAFE_ERRORS.any? { |klass| error.is_a?(klass) }

      error.class.name
    end
  end
end
