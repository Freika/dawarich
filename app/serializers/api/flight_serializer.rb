# frozen_string_literal: true

module Api
  class FlightSerializer
    def initialize(flight)
      @flight = flight
    end

    def call
      {
        type: 'Feature',
        geometry: {
          type: 'LineString',
          coordinates: [[@flight.from_lon, @flight.from_lat], [@flight.to_lon, @flight.to_lat]]
        },
        properties: {
          id: @flight.id,
          from_code: @flight.from_code, to_code: @flight.to_code,
          from_name: @flight.from_name, to_name: @flight.to_name,
          airline_name: @flight.airline_name, flight_number: @flight.flight_number,
          flight_date: @flight.flight_date, departure_time: @flight.departure_time,
          arrival_time: @flight.arrival_time, seat: @flight.seat,
          seat_class: @flight.seat_class, distance_km: @flight.distance_km
        }
      }
    end
  end
end
