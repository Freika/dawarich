# frozen_string_literal: true

module Flights
  module ExternalId
    FILE_ID_OFFSET = 2_000_000_000
    FLIGHTDIARY_FILE_ID_OFFSET = 3_000_000_000

    module_function

    def for_airtrail_file(flight)
      return flight['id'].to_i if flight['id'].present?

      from = flight['from']
      to = flight['to']
      from_code = from.is_a?(Hash) ? from['icao'] : from
      to_code = to.is_a?(Hash) ? to['icao'] : to

      key = [
        flight['date'],
        from_code,
        to_code,
        flight['departure'],
        flight['flightNumber']
      ].join('|')

      FILE_ID_OFFSET + (Zlib.crc32(key) % 1_000_000_000)
    end

    def for_flightdiary_file(parts)
      key = [
        'flightdiary',
        parts[:date],
        parts[:from_icao],
        parts[:to_icao],
        parts[:departure],
        parts[:flight_number]
      ].join('|')

      FLIGHTDIARY_FILE_ID_OFFSET + (Zlib.crc32(key) % 1_000_000_000)
    end
  end
end
