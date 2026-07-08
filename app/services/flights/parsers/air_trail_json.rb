# frozen_string_literal: true

module Flights
  module Parsers
    class AirTrailJson
      def self.call(data)
        new(data).call
      end

      def initialize(data)
        @data = data
      end

      def call
        flights = extract_flights(@data)
        raise Error, 'No flights found in JSON' if flights.empty?

        flights.map { |flight| normalize(flight) }
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

      def normalize(flight)
        raise Error, 'Each flight must be a JSON object' unless flight.is_a?(Hash)

        flight = flight.deep_dup
        flight['id'] = Flights::ExternalId.for_airtrail_file(flight) if flight['id'].blank?
        flight
      end
    end
  end
end
