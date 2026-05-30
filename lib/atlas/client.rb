# frozen_string_literal: true

module Atlas
  # Client for the Atlas geocoding HTTP API (`/api/v1`).
  #
  # MVP scope: batch forward geocoding (`POST /api/v1/geocode/batch`) and
  # batch reverse geocoding (`POST /api/v1/reverse/batch`). The single-item
  # `#search` / `#reverse` methods exist for drop-in compatibility with
  # Geocoder::Search and are implemented on top of the batch endpoints, so
  # every outbound request the client makes is a batch request.
  class Client
    class Error < StandardError; end
    class Unauthorized < Error; end
    class RateLimited < Error; end
    class ServerError < Error; end
    class ToolDisabled < Error; end

    API_PREFIX = '/api/v1'
    GEOCODE_BATCH_PATH = "#{API_PREFIX}/geocode/batch".freeze
    REVERSE_BATCH_PATH = "#{API_PREFIX}/reverse/batch".freeze
    DEFAULT_SEARCH_LIMIT = 10

    def initialize(configuration = Atlas.configuration)
      @configuration = configuration
    end

    # @param queries [Array<String, Hash>] each a query string or { q:, limit: }
    # @return [Array<Array<Atlas::Result>>] one match list per `results` entry
    #   returned by Atlas, in response order. Aligned to input order only when
    #   Atlas echoes one entry per query (it does not pad missing queries).
    def geocode_batch(queries, lang: nil)
      ensure_tool_enabled!(:geocoding)

      payload = { queries: queries.map { |query| normalize_query(query) } }
      payload[:lang] = lang if lang

      body = post(GEOCODE_BATCH_PATH, payload)

      Array(body['results']).map do |entry|
        Array(entry['matches']).map { |row| Result.new(row) }
      end
    end

    # @param coordinates [Array<Array(Numeric, Numeric), Hash>] [lat, lon] or { lat:, lon:, zoom: }
    # @return [Array<Atlas::Result, nil>] one result (or nil) per `results` entry
    #   returned by Atlas, in response order. Aligned to input order only when
    #   Atlas echoes one entry per coordinate (it does not pad missing entries).
    def reverse_geocode_batch(coordinates, lang: nil)
      ensure_tool_enabled!(:geocoding)

      payload = { coordinates: coordinates.map { |coord| normalize_coordinate(coord) } }
      payload[:lang] = lang if lang

      body = post(REVERSE_BATCH_PATH, payload)

      Array(body['results']).map do |entry|
        row = entry['result']
        row && Result.new(row)
      end
    end

    # Drop-in replacement for Geocoder::ApiClient#search.
    # @return [Hash] body-shaped hash: { 'results' => [row, ...] }
    def search(query, limit: DEFAULT_SEARCH_LIMIT, **_opts)
      matches = geocode_batch([{ q: query, limit: limit }]).first || []
      { 'results' => matches.map(&:data) }
    end

    # Drop-in replacement for Geocoder::ApiClient#reverse.
    # @return [Hash] body-shaped hash: { 'results' => [row, ...] }
    def reverse(lat, lon)
      result = reverse_geocode_batch([[lat, lon]]).first
      { 'results' => [result&.data].compact }
    end

    private

    def ensure_tool_enabled!(tool)
      return if @configuration.tool_enabled?(tool)

      raise ToolDisabled, "Atlas tool '#{tool}' is not enabled (see ATLAS_ENABLED_TOOLS)"
    end

    def normalize_query(query)
      case query
      when Hash
        q = query[:q] || query['q']
        raise ArgumentError, "geocode query is missing :q (got #{query.inspect})" if q.nil?

        { q: q, limit: query[:limit] || query['limit'] }.compact
      else
        { q: query }
      end
    end

    def normalize_coordinate(coord)
      case coord
      when Hash
        { lat: coord[:lat] || coord['lat'],
          lon: coord[:lon] || coord['lon'],
          zoom: coord[:zoom] || coord['zoom'] }.compact
      else
        lat, lon = coord
        { lat: lat, lon: lon }
      end
    end

    def post(path, payload)
      response = connection.post(path) do |req|
        req.headers['Content-Type'] = 'application/json'
        req.body = payload.to_json
      end

      handle_response(response)
    rescue Faraday::Error => e
      raise Error, "Atlas request failed: #{e.message}"
    end

    def handle_response(response)
      status = response.status
      return parse(response.body) if status == 200

      raise Unauthorized, error_message(response, 'Invalid API key') if status == 401
      raise RateLimited, error_message(response, 'Rate limit exceeded') if status == 429
      raise ServerError, error_message(response, "Server error: #{status}") if status >= 500

      message = error_message(response, "Unexpected response: #{status}")
      Rails.logger.warn("Atlas request returned #{status}: #{message}")
      raise Error, message
    end

    def error_message(response, fallback)
      parsed = JSON.parse(response.body)
      (parsed.is_a?(Hash) && parsed.dig('error', 'message')) || fallback
    rescue JSON::ParserError
      fallback
    end

    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise Error, "Invalid JSON response: #{e.message}"
    end

    def connection
      @connection ||= Faraday.new(url: @configuration.url) do |conn|
        conn.request :authorization, 'Bearer', @configuration.api_key if @configuration.api_key.present?
        conn.options.timeout = @configuration.timeout
        conn.options.open_timeout = @configuration.timeout
      end
    end
  end
end
