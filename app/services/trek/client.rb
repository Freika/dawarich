# frozen_string_literal: true

module Trek
  class Client
    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end
    end

    TIMEOUT = 10.seconds
    UNTRUSTED_CERTIFICATE = Regexp.union(
      /self[- ]signed certificate/, 'unable to get local issuer certificate', 'unable to verify the first certificate'
    )
    SKIP_SSL_HINT = '. If TREK uses a self-signed or private CA certificate, reconnect it with ' \
                    '"Skip SSL certificate verification" turned on'

    def initialize(source)
      @source = source
    end

    def trips
      response = get('/api/v1/trips')
      payload = parse_json(response)
      raise Error, 'TREK response does not contain a trip list' unless payload.is_a?(Hash)

      trips = payload['trips']
      raise Error, 'TREK response does not contain trips' unless trips.is_a?(Array)

      identifiers = trips.filter_map { |trip| normalized_identifier(trip['id']) if trip.is_a?(Hash) }
      unless identifiers.length == trips.length && identifiers.uniq.length == identifiers.length
        raise Error, 'TREK trip list contains an invalid trip'
      end

      trips
    end

    def trip(identifier)
      payload = parse_json(get("/api/v1/trips/#{CGI.escape(identifier.to_s)}"))
      raise Error, 'TREK response does not contain a trip' unless payload.is_a?(Hash)

      payload
    end

    private

    def normalized_identifier(identifier)
      return identifier.to_s if identifier.is_a?(Integer)
      return identifier if identifier.is_a?(String) && identifier.present?

      nil
    end

    def get(path)
      response = Integrations::Transport.request(
        :get, "#{@source.base_url}#{path}",
        headers: { 'Authorization' => "Bearer #{@source.api_key}", 'Accept' => 'application/json' },
        skip_ssl_verification: @source.skip_ssl_verification,
        timeout: TIMEOUT
      )
      return response if response.success?

      raise Error.new("TREK request failed with HTTP #{response.code}", status: response.code)
    rescue Integrations::Transport::Error => e
      raise Error.new("TREK request failed with HTTP #{e.status}", status: e.status) if e.status
      raise Error, "TREK URL was rejected: #{e.message}" if e.blocked? || e.unresolvable?

      raise Error, "TREK connection failed: #{e.message}#{skip_ssl_hint(e)}"
    end

    def skip_ssl_hint(error)
      return unless error.certificate? && error.message.match?(UNTRUSTED_CERTIFICATE)

      SKIP_SSL_HINT unless @source.skip_ssl_verification
    end

    def parse_json(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Error, 'TREK returned invalid JSON'
    end
  end
end
