# frozen_string_literal: true

# Straight-line distance for in-memory checks on a stream of points.
module GeoDistance
  def self.meters(from, to)
    Geocoder::Calculations.distance_between(from, to, units: :km) * 1000
  end
end
