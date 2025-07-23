# frozen_string_literal: true

module Distanceable
  extend ActiveSupport::Concern

  module ClassMethods
    def total_distance(points = nil, unit = :km)
      # Handle method being called directly on relation vs with array
      if points.nil?
        calculate_distance_for_relation(unit)
      else
        calculate_distance_for_array(points, unit)
      end
    end

    private

    def calculate_distance_for_relation(unit)
      unless ::DISTANCE_UNITS.key?(unit.to_sym)
        raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
      end

      distance_in_meters = connection.select_value(<<-SQL.squish)
        WITH points_with_previous AS (
          SELECT
            lonlat,
            LAG(lonlat) OVER (ORDER BY timestamp) as prev_lonlat
          FROM (#{to_sql}) AS points
        )
        SELECT COALESCE(
          SUM(
            ST_Distance(
              lonlat::geography,
              prev_lonlat::geography
            )
          ),
          0
        )
        FROM points_with_previous
        WHERE prev_lonlat IS NOT NULL
      SQL

      distance_in_meters.to_f / ::DISTANCE_UNITS[unit.to_sym]
    end

    def calculate_distance_for_array(points, unit = :km)
      unless ::DISTANCE_UNITS.key?(unit.to_sym)
        raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
      end

      return 0 if points.length < 2

      # OPTIMIZED: Single SQL query instead of N individual queries
      total_meters = calculate_batch_distances(points).sum

      total_meters.to_f / ::DISTANCE_UNITS[unit.to_sym]
    end

    # Optimized batch distance calculation using single SQL query
    def calculate_batch_distances(points)
      return [] if points.length < 2

      point_pairs = points.each_cons(2).to_a
      return [] if point_pairs.empty?

      # Create a VALUES clause with all point pairs
      values_clause = point_pairs.map.with_index do |(p1, p2), index|
        "(#{index}, ST_GeomFromEWKT('#{p1.lonlat}')::geography, ST_GeomFromEWKT('#{p2.lonlat}')::geography)"
      end.join(', ')

      # Single query to calculate all distances
      results = connection.execute(<<-SQL.squish)
        WITH point_pairs AS (
          SELECT 
            pair_id,
            point1,
            point2
          FROM (VALUES #{values_clause}) AS t(pair_id, point1, point2)
        )
        SELECT 
          pair_id,
          ST_Distance(point1, point2) as distance_meters
        FROM point_pairs
        ORDER BY pair_id
      SQL

      # Return array of distances in meters
      results.map { |row| row['distance_meters'].to_f }
    end
  end

  def distance_to(other_point, unit = :km)
    unless ::DISTANCE_UNITS.key?(unit.to_sym)
      raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
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
    distance_in_meters.to_f / ::DISTANCE_UNITS[unit.to_sym]
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
    end
  end
end
