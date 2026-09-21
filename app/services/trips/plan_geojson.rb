# frozen_string_literal: true

module Trips
  # The trip plan as GeoJSON for the map: numbered stops per day (numbers match
  # the plan card, so stops without coordinates still take their place), a
  # straight line through each day's located stops, stays and loose places.
  class PlanGeojson
    def initialize(trip)
      @trip = trip
    end

    def call
      features = day_features + place_features(@trip.planned_accommodations, 'stay') +
                 place_features(@trip.planned_unplanned_places, 'unplanned')
      { type: 'FeatureCollection', features: } if features.any?
    end

    private

    def day_features
      @trip.planned_days.each_with_index.flat_map do |day, day_index|
        stops = day.planned_stops.each_with_index.filter_map do |stop, stop_index|
          next unless located?(stop)

          point(stop, kind: 'stop', name: stop.name, day: day_index, number: stop_index + 1)
        end
        stops + route(stops, day_index)
      end
    end

    def route(stops, day_index)
      return [] if stops.size < 2

      [{
        type: 'Feature',
        geometry: { type: 'LineString', coordinates: stops.map { |stop| stop[:geometry][:coordinates] } },
        properties: { kind: 'route', day: day_index }
      }]
    end

    def place_features(places, kind)
      places.select { |place| located?(place) }.map { |place| point(place, kind:, name: place.name) }
    end

    def point(record, **properties)
      {
        type: 'Feature',
        geometry: { type: 'Point', coordinates: [record.longitude.to_f, record.latitude.to_f] },
        properties:
      }
    end

    def located?(record)
      record.latitude.present? && record.longitude.present?
    end
  end
end
