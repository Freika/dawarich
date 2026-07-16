# frozen_string_literal: true

require 'csv'

module Flights
  module Parsers
    class FlightDiaryCsv
      KEY = :flightdiary_csv
      LABEL = 'FlightDiary CSV'
      EXTENSIONS = %w[.csv].freeze

      AIRPORT_PATTERN = %r{\A(?<name>.*?)\s*\((?<iata>[A-Z0-9]{3})/(?<icao>[A-Z0-9]{4})\)\s*\z}i
      AIRLINE_PATTERN = %r{\A(?<name>.*?)\s*\((?<iata>[A-Z0-9]{2})/(?<icao>[A-Z0-9]{3})\)\s*\z}i
      AIRCRAFT_PATTERN = /\A(?<name>.*?)\s*\((?<code>[A-Z0-9-]+)\)\s*\z/i

      REQUIRED_HEADERS = %w[Date From To].freeze

      def self.key = KEY
      def self.label = LABEL
      def self.extensions = EXTENSIONS

      def self.detect?(data)
        return false unless data.is_a?(Array) && data.first.is_a?(Hash)

        headers = data.first.keys.map(&:to_s)
        REQUIRED_HEADERS.all? { |h| headers.include?(h) } &&
          (headers.include?('Flight number') || headers.include?('Dep time'))
      end

      def self.decode(content, strict: false)
        cleaned = content.to_s.delete_prefix("\uFEFF").sub(/\A(?:\r?\n)+/, '')
        CSV.parse(cleaned, headers: true, liberal_parsing: true)
           .map(&:to_h)
           .reject { |row| row.values.all?(&:blank?) }
      rescue CSV::MalformedCSVError => e
        raise Error, "Invalid CSV: #{e.message}" if strict

        nil
      end

      def self.call(data)
        new(data).call
      end

      def initialize(data)
        @data = data
      end

      def call
        flights = @data.filter_map { |row| map_row(row) }
        raise Error, 'No flights found in CSV' if flights.empty?

        flights
      end

      private

      def map_row(row)
        return nil if row['Date'].blank? && row['From'].blank? && row['To'].blank?

        from = parse_airport(row['From'])
        to = parse_airport(row['To'])
        from_lookup = AirportLookup.call(icao: from[:icao], iata: from[:iata])
        to_lookup = AirportLookup.call(icao: to[:icao], iata: to[:iata])
        airline = parse_airline(row['Airline'])
        aircraft_name = parse_aircraft_name(row['Aircraft'])

        departure_time = combine_datetime(row['Date'], row['Dep time'], from_lookup&.dig(:tz_name))
        arrival_time = combine_datetime(
          row['Date'],
          row['Arr time'],
          to_lookup&.dig(:tz_name),
          overnight_after_tod: row['Dep time']
        )

        flight_number = row['Flight number'].to_s.strip.presence
        external_id = ExternalId.for_flightdiary_file(
          date: row['Date'],
          from_icao: from[:icao] || from_lookup&.dig(:icao),
          to_icao: to[:icao] || to_lookup&.dig(:icao),
          departure: row['Dep time'],
          flight_number: flight_number
        )

        {
          external_id: external_id,
          flight_date: parse_date(row['Date']),
          date_precision: 'day',
          departure_time: departure_time,
          arrival_time: arrival_time,
          from_code: from[:icao] || from_lookup&.dig(:icao),
          from_name: from_lookup&.dig(:name) || from[:name],
          from_lat: from_lookup&.dig(:lat),
          from_lon: from_lookup&.dig(:lon),
          to_code: to[:icao] || to_lookup&.dig(:icao),
          to_name: to_lookup&.dig(:name) || to[:name],
          to_lat: to_lookup&.dig(:lat),
          to_lon: to_lookup&.dig(:lon),
          airline_name: airline[:name],
          airline_iata: airline[:iata],
          aircraft_name: aircraft_name,
          aircraft_reg: row['Registration'].to_s.strip.presence,
          flight_number: flight_number,
          seat: row['Seat number'].to_s.strip.presence,
          seat_class: map_flight_class(row['Flight class']),
          note: row['Note'].to_s.strip.presence,
          distance_km: haversine(from_lookup&.dig(:lat), from_lookup&.dig(:lon),
                                 to_lookup&.dig(:lat), to_lookup&.dig(:lon)),
          raw: row
        }
      end

      def parse_airport(value)
        text = value.to_s.strip
        match = AIRPORT_PATTERN.match(text)
        if match
          {
            name: match[:name].strip.presence,
            iata: match[:iata].upcase,
            icao: match[:icao].upcase
          }
        else
          { name: text.presence, iata: nil, icao: nil }
        end
      end

      def parse_airline(value)
        text = value.to_s.strip
        return { name: nil, iata: nil } if text.blank? || text == '(/)' || text == '()'

        match = AIRLINE_PATTERN.match(text)
        if match
          { name: match[:name].strip.presence, iata: match[:iata].upcase }
        else
          { name: text.presence, iata: nil }
        end
      end

      def parse_aircraft_name(value)
        text = value.to_s.strip
        return nil if text.blank? || text == '()'

        match = AIRCRAFT_PATTERN.match(text)
        name = match ? match[:name].strip : text
        name.presence
      end

      def parse_date(value)
        return nil if value.blank?

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def combine_datetime(date_str, time_str, tz_name, overnight_after_tod: nil)
        date = parse_date(date_str)
        return nil if date.nil? || time_str.blank?

        time_parts = time_str.to_s.strip.match(/\A(\d{1,2}):(\d{2})(?::(\d{2}))?\z/)
        return nil unless time_parts

        zone = time_zone_for(tz_name)
        local = zone.local(
          date.year, date.month, date.day,
          time_parts[1].to_i, time_parts[2].to_i, (time_parts[3] || 0).to_i
        )

        if overnight_after_tod.present? && time_of_day_seconds(time_str) < time_of_day_seconds(overnight_after_tod)
          local += 1.day
        end

        local
      rescue ArgumentError, TypeError
        nil
      end

      def time_of_day_seconds(time_str)
        parts = time_str.to_s.strip.match(/\A(\d{1,2}):(\d{2})(?::(\d{2}))?\z/)
        return 0 unless parts

        (parts[1].to_i * 3600) + (parts[2].to_i * 60) + (parts[3] || 0).to_i
      end

      def time_zone_for(tz_name)
        return Time.zone if tz_name.blank?

        ActiveSupport::TimeZone[tz_name] || Time.find_zone(tz_name) || Time.zone
      end

      def map_flight_class(value)
        case value.to_s.strip
        when '1' then 'economy'
        when '2' then 'business'
        when '3' then 'first'
        else value.to_s.strip.presence
        end
      end

      def haversine(lat1, lon1, lat2, lon2)
        return nil unless [lat1, lon1, lat2, lon2].all?

        earth_radius_km = 6371.0
        to_rad = ->(d) { d * Math::PI / 180 }
        dlat = to_rad.call(lat2 - lat1)
        dlon = to_rad.call(lon2 - lon1)
        a = (Math.sin(dlat / 2)**2) +
            (Math.cos(to_rad.call(lat1)) * Math.cos(to_rad.call(lat2)) * (Math.sin(dlon / 2)**2))
        (earth_radius_km * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))).round(1)
      end
    end
  end
end
