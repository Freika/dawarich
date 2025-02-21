# frozen_string_literal: true

module Distanceable
  extend ActiveSupport::Concern

  DISTANCE_UNITS = {
    km: 1000, # to meters
    mi: 1609.34, # to meters
    m: 1, # already in meters
    ft: 0.3048, # to meters
    yd: 0.9144 # to meters
  }.freeze

  def distance_to(other_point, unit = :km)
    unless DISTANCE_UNITS.key?(unit.to_sym)
      raise ArgumentError, "Invalid unit. Supported units are: #{DISTANCE_UNITS.keys.join(', ')}"
    end

    # Extract coordinates based on what type other_point is
    other_lonlat = extract_point(other_point)
    return nil if other_lonlat.nil?

    # Calculate distance in meters using PostGIS
    distance_in_meters = self.class.connection.select_value(<<-SQL.squish)
      SELECT ST_Distance(
        ST_GeomFromEWKT('#{lonlat}')::geography,
        ST_GeomFromEWKT('#{other_lonlat}')::geography
      )
    SQL

    # Convert to requested unit
    distance_in_meters.to_f / DISTANCE_UNITS[unit.to_sym]
  end

  private

  def extract_point(point)
    case point
    when Array
      unless point.length == 2
        raise ArgumentError,
              'Coordinates array must contain exactly 2 elements [latitude, longitude]'
      end

      RGeo::Geographic.spherical_factory(srid: 4326).point(point[1], point[0])
    when self.class
      point.lonlat
    else
      nil
    end
  end
end
