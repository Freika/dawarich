# frozen_string_literal: true

require 'net/http'

module MapMatching
  module Atlas
    class Client
      Result = Data.define(:geometry, :stats, :meta)

      class Error < StandardError
        attr_reader :status, :code, :retry_after

        def initialize(message, code:, status: nil, retry_after: nil)
          super(message)
          @status = status
          @code = code
          @retry_after = retry_after
        end

        def transient?
          false
        end
      end

      class RetryableError < Error
        def transient?
          true
        end
      end

      class InvalidRequest < Error; end
      class RateLimited < RetryableError; end
      class Unavailable < RetryableError; end
      class ProviderError < Error; end
      class MalformedResponse < RetryableError; end

      OPEN_TIMEOUT = 5.seconds
      READ_TIMEOUT = 70.seconds

      def initialize(base_url: DawarichSettings.atlas_url)
        @endpoint = Endpoint.new(base_url)
      end

      def health
        data = envelope_data(request(:get, '/api/v1/health'))
        capabilities = data['capabilities']
        routing = capabilities['routing'] if capabilities.is_a?(Hash)
        malformed! unless data['status'].is_a?(String) && routing.is_a?(String)

        { status: data['status'], routing: routing }
      end

      def version
        data = envelope_data(request(:get, '/api/v1/version'))
        malformed! unless data['version'].is_a?(String)

        { version: data['version'], revision: data['revision'].to_s.presence }
      end

      def map_match(shape:, mode:)
        payload = request(
          :post,
          '/api/v1/map-match',
          body: {
            shape: shape,
            mode: mode,
            shape_match: 'map_snap',
            format: 'geojson',
            include_directions: false
          }
        )
        data = envelope_data(payload)
        geometry = data['geometry']
        stats = data['stats']
        malformed! unless valid_geometry?(geometry) && stats.is_a?(Hash) && payload['meta'].is_a?(Hash)

        Result.new(geometry:, stats:, meta: payload['meta'])
      end

      private

      attr_reader :endpoint

      def request(method, path, body: nil)
        uri = endpoint.uri_for(path)
        http = Net::HTTP.new(uri.host, uri.port, nil)
        http.ipaddr = endpoint.resolved_ip!
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT

        request = request_for(method, uri, body)
        response = http.start { |connection| connection.request(request) }
        handle_response(response)
      rescue UrlValidatable::BlockedUrlError => e
        raise Error.new("Atlas URL was rejected: #{e.message}", code: 'invalid_url')
      rescue *Photos::ConnectionErrors::RETRYABLE => e
        raise Unavailable.new("Atlas connection failed: #{e.class}", code: 'connection_failed')
      end

      def request_for(method, uri, body)
        headers = { 'Accept' => 'application/json' }
        return Net::HTTP::Get.new(uri.request_uri, headers) if method == :get

        Net::HTTP::Post.new(uri.request_uri, headers.merge('Content-Type' => 'application/json')).tap do |request|
          request.body = JSON.generate(body)
        end
      end

      def handle_response(response)
        return parse_json(response.body) if response.is_a?(Net::HTTPSuccess)

        status = response.code.to_i
        retry_after = Integer(response['Retry-After'], exception: false)
        case status
        when 400, 422
          raise InvalidRequest.new('Atlas rejected the map-matching input', status:, code: 'invalid_input')
        when 429
          raise RateLimited.new('Atlas map matching is at capacity', status:, code: 'capacity', retry_after:)
        when 502, 503
          raise Unavailable.new('Atlas routing backend is unavailable', status:, code: 'unavailable')
        else
          raise ProviderError.new("Atlas request failed with HTTP #{status}", status:, code: 'http_error')
        end
      end

      def parse_json(body)
        JSON.parse(body).tap { |payload| malformed! unless payload.is_a?(Hash) }
      rescue JSON::ParserError
        malformed!
      end

      def envelope_data(payload)
        payload['data'].tap { |data| malformed! unless data.is_a?(Hash) }
      end

      def valid_geometry?(geometry)
        return false unless geometry.is_a?(Hash)
        return false unless %w[LineString MultiLineString].include?(geometry['type'])

        geometry['coordinates'].is_a?(Array) && geometry['coordinates'].present?
      end

      def malformed!
        raise MalformedResponse.new('Atlas returned a malformed response', code: 'malformed_response')
      end
    end
  end
end
