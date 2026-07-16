# frozen_string_literal: true

module Flights
  class AirportLookup
    def self.call(icao: nil, iata: nil)
      new.call(icao: icao, iata: iata)
    end

    def call(icao: nil, iata: nil)
      airport = find_airport(icao: icao, iata: iata)
      return nil if airport.nil?

      {
        icao: blank_to_nil(airport.icao),
        iata: blank_to_nil(airport.iata),
        name: blank_to_nil(airport.name),
        lat: parse_float(airport.latitude),
        lon: parse_float(airport.longitude),
        tz_name: blank_to_nil(airport.tz_name)
      }
    end

    private

    def find_airport(icao:, iata:)
      if icao.present?
        # airports gem API (not ActiveRecord)
        found = ::Airports.find_by_icao_code(icao.to_s.upcase) # rubocop:disable Rails/DynamicFindBy
        return found if found
      end

      return nil if iata.blank?

      ::Airports.find_by_iata_code(iata.to_s.upcase) # rubocop:disable Rails/DynamicFindBy
    end

    def blank_to_nil(value)
      value = value.to_s.strip
      return nil if value.blank? || value == '\\N'

      value
    end

    def parse_float(value)
      return nil if value.blank? || value.to_s == '\\N'

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
