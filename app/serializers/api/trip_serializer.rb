# frozen_string_literal: true

class Api::TripSerializer
  def initialize(trip, include_path: false)
    @trip = trip
    @include_path = include_path
  end

  def call
    payload = {
      id: trip.id,
      name: trip.name,
      description: trip.description&.to_plain_text,
      description_html: trip.description&.body&.to_html,
      started_at: trip.started_at,
      ended_at: trip.ended_at,
      distance_meters: trip.distance,
      visited_countries: visited_countries,
      created_at: trip.created_at,
      updated_at: trip.updated_at
    }
    payload[:path] = path_coordinates if include_path
    payload
  end

  private

  attr_reader :trip, :include_path

  def visited_countries
    countries = trip.visited_countries
    countries.is_a?(Array) ? countries : []
  end

  # [[lon, lat], ...] in the same order as GeoJSON LineString coordinates.
  def path_coordinates
    return [] if trip.path.blank?

    trip.path.points.map { [_1.x, _1.y] }
  end
end
