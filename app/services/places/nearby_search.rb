# frozen_string_literal: true

module Places
  class NearbySearch
    RADIUS_KM = 0.5
    MAX_RESULTS = 10
    CACHE_TTL = 1.hour
    GRID_PRECISION = 4

    def initialize(user:, latitude:, longitude:, radius: RADIUS_KM, limit: MAX_RESULTS, cache: false)
      @user = user
      @latitude = latitude.to_f
      @longitude = longitude.to_f
      @radius = radius
      @limit = limit
      @cache = cache
    end

    def call
      return [] unless reverse_geocoding_enabled?
      return [] if @latitude.zero? && @longitude.zero?

      results = if @cache
                  Rails.cache.fetch(cache_key, expires_in: CACHE_TTL, skip_nil: true) { fetch_and_format }
                else
                  fetch_and_format
                end
      results || []
    rescue *ReverseGeocoding::ProviderErrors::SEARCH_HANDLED => e
      log_provider_error(e)
      []
    rescue StandardError => e
      if ReverseGeocoding::ProviderErrors.transient_tls?(e)
        log_provider_error(e)
      else
        Rails.logger.error("Nearby search failed: #{e.class}: #{e.message}")
        ExceptionReporter.call(e, 'Places::NearbySearch failed')
      end
      []
    end

    private

    def log_provider_error(error)
      Rails.logger.warn("Nearby search provider error: #{error.class} (radius: #{@radius}, limit: #{@limit})")
    end

    def reverse_geocoding_enabled?
      geocoding_config.enabled?
    end

    def geocoding_config
      @geocoding_config ||= Geocoding::Config.for(@user)
    end

    def cache_key
      "places_nearby:#{geocoding_config.cache_digest}:" \
        "#{@latitude.round(GRID_PRECISION)},#{@longitude.round(GRID_PRECISION)},r=#{@radius},l=#{@limit}"
    end

    def fetch_and_format
      results = Geocoding::Search.call(
        user: @user,
        query: [@latitude, @longitude],
        timeout: REVERSE_GEOCODING_TIMEOUT,
        limit: @limit,
        max_wait: Geocoding::RateLimiter::MAX_INTERACTIVE_WAIT,
        distance_sort: true,
        radius: @radius,
        units: :km
      )
      return if results.nil?

      format_results(results)
    end

    def format_results(results)
      results.map do |result|
        Places::PhotonResultFormatter.call(result, fallback_lat: @latitude, fallback_lon: @longitude)
      end
    end
  end
end
