# frozen_string_literal: true

module Places
  class Search
    MAX_RESULTS = 10
    FETCH_LIMIT = 50
    MIN_QUERY_LENGTH = 2
    MAX_QUERY_LENGTH = 200

    def initialize(query:, latitude:, longitude:, radius:, limit: MAX_RESULTS)
      @query = query.to_s.strip.first(MAX_QUERY_LENGTH)
      @latitude = latitude.to_f
      @longitude = longitude.to_f
      @radius = radius.to_f
      @limit = limit
    end

    def call
      return [] unless DawarichSettings.reverse_geocoding_enabled?
      return [] if @query.length < MIN_QUERY_LENGTH

      fetch_and_filter
    rescue StandardError => e
      ExceptionReporter.call(e, "Places::Search failed for '#{@query}' near #{@latitude},#{@longitude}")
      []
    end

    private

    def fetch_and_filter
      Geocoder.search(@query, limit: FETCH_LIMIT, bias: { latitude: @latitude, longitude: @longitude })
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
