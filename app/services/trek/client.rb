# frozen_string_literal: true

require 'digest'

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
      @source.verify_base_url!

      response = HTTParty.get(
        "#{@source.base_url}#{path}",
        headers: {
          'Authorization' => "Bearer #{@source.api_key}",
          'Accept' => 'application/json'
        },
        timeout: TIMEOUT,
        follow_redirects: false
      )

      return response if response.success?

      raise Error.new("TREK request failed with HTTP #{response.code}", status: response.code.to_i)
    rescue UrlValidatable::BlockedUrlError => e
      raise Error, "TREK URL was rejected: #{e.message}"
    rescue *Photos::ConnectionErrors::HANDLED => e
      raise Error, "TREK connection failed: #{e.message}"
    end

    def parse_json(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise Error, 'TREK returned invalid JSON'
    end
  end
end
