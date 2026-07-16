# frozen_string_literal: true

module Flights
  module Parsers
    class AirTrailJson
      KEY = :airtrail_json
      LABEL = 'AirTrail JSON (v3)'
      EXTENSIONS = %w[.json].freeze

      def self.key = KEY
      def self.label = LABEL
      def self.extensions = EXTENSIONS

      def self.detect?(data)
        data.is_a?(Array) || (data.is_a?(Hash) && data['flights'].is_a?(Array))
      end

      def self.decode(content, strict: false)
        JSON.parse(content)
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON: #{e.message}" if strict

        nil
      end

      def self.call(data)
        new(data).call
      end

      def initialize(data)
        @data = data
      end

      def call
        flights = extract_flights(@data)
        raise Error, 'No flights found in JSON' if flights.empty?

        flights.map { |flight| map_flight(flight) }
      end

      private

      def extract_flights(data)
        case data
        when Array
          data
        when Hash
          if data['flights'].is_a?(Array)
            data['flights']
          elsif data['success'] == false
            raise Error, 'AirTrail JSON indicates an unsuccessful response'
          else
            []
          end
        else
          []
        end
      end

      def map_flight(flight)
        raise Error, 'Each flight must be a JSON object' unless flight.is_a?(Hash)

        flight = flight.deep_dup
        flight['id'] = Flights::ExternalId.for_airtrail_file(flight) if flight['id'].blank?
        AirTrail::FlightMapper.new(flight).attributes
      end
    end
  end
end
