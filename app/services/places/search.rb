# frozen_string_literal: true

module Places
  class Search
    MAX_RESULTS = 10
    FETCH_LIMIT = 50
    MIN_QUERY_LENGTH = 2
    MAX_QUERY_LENGTH = 200

    POLAR_LATITUDE_THRESHOLD = 89.0

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
      config = Geocoding::Config.for(@user)
      options = {
        limit: FETCH_LIMIT,
        max_wait: Geocoding::RateLimiter::MAX_INTERACTIVE_WAIT,
        bias: { latitude: @latitude, longitude: @longitude }
      }

      spatial_params = bounding_box_params(config.provider)
      options[:params] = spatial_params if spatial_params.present?

      results = Geocoding::Search.call(user: @user, query: @query, **options)
      return [] if results.nil?

      results
        .map { |r| Places::PhotonResultFormatter.call(r, fallback_lat: @latitude, fallback_lon: @longitude) }
        .filter_map { |place| within_radius(place) }
        .sort_by { |place| place[:distance] }
        .first(@limit)
        .map { |place| place.except(:distance) }
    end

    def bounding_box_params(provider)
      bbox = computed_bounding_box
      return {} if bbox.nil?

      min_lat, min_lon, max_lat, max_lon = bbox

      case provider&.to_sym
      when :nominatim, :locationiq
        { viewbox: "#{min_lon},#{max_lat},#{max_lon},#{min_lat}", bounded: 1 }
      when :geoapify
        { filter: "rect:#{min_lon},#{min_lat},#{max_lon},#{max_lat}" }
      else
        { bbox: "#{min_lon},#{min_lat},#{max_lon},#{max_lat}" }
      end
    end

    def computed_bounding_box
      return nil if @radius <= 0 || !valid_coordinates?
      # Longitude degree distance approaches zero near poles; fall back to distance bias to avoid box distortion
      return nil if @latitude.abs >= POLAR_LATITUDE_THRESHOLD

      box = Geocoder::Calculations.bounding_box([@latitude, @longitude], @radius, units: :km)
      return nil unless box

      min_lat, min_lon, max_lat, max_lon = box
      return nil if min_lon < -180.0 || max_lon > 180.0

      min_lat = min_lat.clamp(-90.0, 90.0).round(6)
      max_lat = max_lat.clamp(-90.0, 90.0).round(6)
      min_lon = min_lon.round(6)
      max_lon = max_lon.round(6)

      # Edge case where place is on the edges of the map
      return nil if min_lat >= max_lat || min_lon >= max_lon

      [min_lat, min_lon, max_lat, max_lon]
    end

    def valid_coordinates?
      @latitude.between?(-90.0, 90.0) && @longitude.between?(-180.0, 180.0)
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
