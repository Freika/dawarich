# frozen_string_literal: true

module Flights
  module Parsers
    class Registry
      PARSERS = {
        airtrail_json: AirTrailJson
      }.freeze

      def self.detect_and_parse(data)
        parser = detect(data)
        parser.call(data)
      end

      def self.detect(data)
        return PARSERS[:airtrail_json] if airtrail_json?(data)

        raise Error,
              'Unsupported flight JSON format. Expected an AirTrail v3 export ' \
              '(object with a "flights" array) or a bare flights array.'
      end

      def self.airtrail_json?(data)
        data.is_a?(Array) || (data.is_a?(Hash) && data['flights'].is_a?(Array))
      end

      private_class_method :airtrail_json?
    end
  end
end
