# frozen_string_literal: true

module Places
  class Search
    MAX_RESULTS = 10
    FETCH_LIMIT = 50
    MIN_QUERY_LENGTH = 2
    MAX_QUERY_LENGTH = 200

    def initialize(user:, query:, latitude:, longitude:, radius:, limit: MAX_RESULTS)
      @user = user
      @query = query.to_s.strip.first(MAX_QUERY_LENGTH)
      @latitude = latitude.to_f
      @longitude = longitude.to_f
      @radius = radius.to_f
      @limit = limit
    end

    def call
      return [] unless Geocoding::Config.for(@user).enabled?
      return [] if @query.length < MIN_QUERY_LENGTH

      fetch_and_filter
    rescue *ReverseGeocoding::ProviderErrors::SEARCH_HANDLED => e
      log_provider_error(e)
      []
    rescue StandardError => e
      if ReverseGeocoding::ProviderErrors.transient_tls?(e)
        log_provider_error(e)
      else
        Rails.logger.error("Place search failed: #{e.class}: #{e.message}")
        ExceptionReporter.call(e, 'Places::Search failed')
      end
      []
    end

    private

    def log_provider_error(error)
      Rails.logger.warn("Place search provider error: #{error.class} (query length: #{@query.length})")
    end

    def fetch_and_filter
      results = Geocoding::Search
                .call(user: @user, query: @query, limit: FETCH_LIMIT,
                      timeout: FORWARD_GEOCODING_TIMEOUT,
                      max_wait: Geocoding::RateLimiter::MAX_INTERACTIVE_WAIT,
                      bias: { latitude: @latitude, longitude: @longitude })
      return [] if results.nil?

      results
        .map { |r| Places::PhotonResultFormatter.call(r, fallback_lat: @latitude, fallback_lon: @longitude) }
        .filter_map { |place| within_radius(place) }
        .sort_by { |place| place[:distance] }
        .first(@limit)
        .map { |place| place.except(:distance) }
    end

    def within_radius(place)
      return nil if place[:latitude].nil? || place[:longitude].nil?

      distance = Geocoder::Calculations.distance_between(
        [@latitude, @longitude], [place[:latitude], place[:longitude]], units: :km
      )
      return nil unless distance.is_a?(Numeric) && distance.finite? && distance <= @radius

      place.merge(distance: distance)
    end
  end
end
