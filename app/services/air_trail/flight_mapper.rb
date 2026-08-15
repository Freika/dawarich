# frozen_string_literal: true

module AirTrail
  class FlightMapper
    EARTH_RADIUS_KM = 6371.0

    def initialize(payload)
      @f = payload
    end

    def attributes
      from = @f['from'] || {}
      to = @f['to'] || {}
      airline = @f['airline'] || {}
      aircraft = @f['aircraft'] || {}
      seat = (@f['seats'] || []).first || {}

      {
        external_id: @f['id'],
        flight_date: @f['date'],
        date_precision: @f['datePrecision'] || 'day',
        departure_time: parse_time(@f['departure']),
        arrival_time: parse_time(@f['arrival']),
        from_code: from['icao'], from_name: from['name'],
        from_lat: from['lat'], from_lon: from['lon'],
        to_code: to['icao'], to_name: to['name'],
        to_lat: to['lat'], to_lon: to['lon'],
        airline_name: airline['name'], airline_iata: airline['iata'],
        aircraft_name: aircraft['name'], aircraft_reg: @f['aircraftReg'],
        flight_number: @f['flightNumber'],
        seat: seat['seat'] || seat['seatNumber'], seat_class: seat['seatClass'],
        note: @f['note'],
        distance_km: haversine(from['lat'], from['lon'], to['lat'], to['lon']),
        raw: @f
      }
    end

    private

    def parse_time(value)
      value.present? ? Time.zone.parse(value) : nil
    rescue ArgumentError
      nil
    end

    def haversine(lat1, lon1, lat2, lon2)
      return nil unless [lat1, lon1, lat2, lon2].all?

      to_rad = ->(d) { d * Math::PI / 180 }
      dlat = to_rad.call(lat2 - lat1)
      dlon = to_rad.call(lon2 - lon1)
      a = (Math.sin(dlat / 2)**2) +
          (Math.cos(to_rad.call(lat1)) * Math.cos(to_rad.call(lat2)) * (Math.sin(dlon / 2)**2))
      (EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))).round(1)
    end
  end
end
