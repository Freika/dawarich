# frozen_string_literal: true

module Distanceable
  extend ActiveSupport::Concern

  module ClassMethods
    def total_distance(points = nil, unit = :km)
      if points.nil?
        calculate_distance_for_relation(unit)
      else
        calculate_distance_for_array(points, unit)
      end
    end

    # In-memory distance calculation using Geocoder (no SQL dependency)
    def calculate_distance_for_array_geocoder(points, unit = :km)
      unless ::DISTANCE_UNITS.key?(unit.to_sym)
        raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
      end

      return 0 if points.length < 2

      total_meters = points.each_cons(2).sum do |p1, p2|
        # Extract coordinates from lonlat (source of truth)

        # Check if lonlat exists and is valid
        if p1.lonlat.nil? || p2.lonlat.nil?
          Rails.logger.warn "Skipping distance calculation for points with nil lonlat: p1(#{p1.id}), p2(#{p2.id})"
          next 0
        end

        lat1 = p1.lat
        lon1 = p1.lon
        lat2 = p2.lat
        lon2 = p2.lon

        # Check for nil coordinates extracted from lonlat
        if lat1.nil? || lon1.nil? || lat2.nil? || lon2.nil?
          Rails.logger.warn(
            'Skipping distance calc for points with nil coordinates: ' \
              "p1(#{p1.id}: #{lat1}, #{lon1}), p2(#{p2.id}: #{lat2}, #{lon2})"
          )
          next 0
        end

        # Check for NaN or infinite coordinates
        if [lat1, lon1, lat2, lon2].any? { |coord| !coord.finite? }
          Rails.logger.warn(
            'Skipping distance calc for points with invalid coordinates: ' \
              "p1(#{p1.id}: #{lat1}, #{lon1}), p2(#{p2.id}: #{lat2}, #{lon2})"
          )
          next 0
        end

        # Check for valid latitude/longitude ranges
        if lat1.abs > 90 || lat2.abs > 90 || lon1.abs > 180 || lon2.abs > 180
          Rails.logger.warn(
            'Skipping distance calc for out-of-range coordinates: ' \
              "p1(#{p1.id}: #{lat1}, #{lon1}), p2(#{p2.id}: #{lat2}, #{lon2})"
          )
          next 0
        end

        distance_km = Geocoder::Calculations.distance_between(
          [lat1, lon1],
          [lat2, lon2],
          units: :km
        )

        # Check if Geocoder returned NaN or infinite value
        unless distance_km.finite?
          Rails.logger.warn(
            "Geocoder returned invalid distance (#{distance_km}) for points: " \
              "p1(#{p1.id}: #{lat1}, #{lon1}), p2(#{p2.id}: #{lat2}, #{lon2})"
          )
          next 0
        end

        distance_km * 1000 # Convert km to meters
      rescue StandardError => e
        Rails.logger.error(
          "Error extracting coordinates from lonlat for points #{p1.id}, #{p2.id}: #{e.message}"
        )
        next 0
      end

      result = total_meters.to_f / ::DISTANCE_UNITS[unit.to_sym]

      # Final validation of result
      unless result.finite?
        Rails.logger.error(
          "Final distance calculation resulted in invalid value (#{result}) for #{points.length} points"
        )
        return 0
      end

      result
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

      total_meters = calculate_batch_distances(points).sum

      total_meters.to_f / ::DISTANCE_UNITS[unit.to_sym]
    end

    def calculate_batch_distances(points)
      return [] if points.length < 2

      point_pairs = points.each_cons(2).to_a
      return [] if point_pairs.empty?

      # Create parameterized placeholders for VALUES clause using ? placeholders
      values_placeholders = point_pairs.map do |_|
        '(?, ST_GeomFromEWKT(?)::geography, ST_GeomFromEWKT(?)::geography)'
      end.join(', ')

      # Flatten parameters: [pair_id, lonlat1, lonlat2, pair_id, lonlat1, lonlat2, ...]
      params = point_pairs.flat_map.with_index do |(p1, p2), index|
        [index, p1.lonlat, p2.lonlat]
      end

      # Single query to calculate all distances using parameterized query
      sql_with_params = ActiveRecord::Base.sanitize_sql_array([<<-SQL.squish] + params)
        WITH point_pairs AS (
          SELECT
            pair_id,
            point1,
            point2
          FROM (VALUES #{values_placeholders}) AS t(pair_id, point1, point2)
        )
        SELECT
          pair_id,
          ST_Distance(point1, point2) as distance_meters
        FROM point_pairs
        ORDER BY pair_id
      SQL

      results = connection.select_all(sql_with_params)

      # Return array of distances in meters
      results.map { |row| row['distance_meters'].to_f }
    end
  end

  def distance_to(other_point, unit = :km)
    unless ::DISTANCE_UNITS.key?(unit.to_sym)
      raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
    end

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

  # In-memory distance calculation using Geocoder (no SQL dependency)
  def distance_to_geocoder(other_point, unit = :km)
    unless ::DISTANCE_UNITS.key?(unit.to_sym)
      raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
    end

    begin
      # Extract coordinates from lonlat (source of truth) for current point
      if lonlat.nil?
        Rails.logger.warn 'Cannot calculate distance: current point has nil lonlat'
        return 0
      end

      current_lat = lat
      current_lon = lon

      other_lat, other_lon = case other_point
                             when Array
                               [other_point[0], other_point[1]]
                             else
                               # For other Point objects, extract from their lonlat too
                               if other_point.respond_to?(:lonlat) && other_point.lonlat.nil?
                                 Rails.logger.warn 'Cannot calculate distance: other point has nil lonlat'
                                 return 0
                               end
                               [other_point.lat, other_point.lon]
                             end

      # Check for nil coordinates extracted from lonlat
      if current_lat.nil? || current_lon.nil? || other_lat.nil? || other_lon.nil?
        Rails.logger.warn(
          'Cannot calculate distance: nil coordinates - ' \
            "current(#{current_lat}, #{current_lon}), other(#{other_lat}, #{other_lon})"
        )
        return 0
      end

      # Check for NaN or infinite coordinates
      coords = [current_lat, current_lon, other_lat, other_lon]
      if coords.any? { |coord| !coord.finite? }
        Rails.logger.warn(
          'Cannot calculate distance: invalid coordinates - ' \
            "current(#{current_lat}, #{current_lon}), other(#{other_lat}, #{other_lon})"
        )
        return 0
      end

      # Check for valid latitude/longitude ranges
      if current_lat.abs > 90 || other_lat.abs > 90 || current_lon.abs > 180 || other_lon.abs > 180
        Rails.logger.warn(
          'Cannot calculate distance: out-of-range coordinates - ' \
            "current(#{current_lat}, #{current_lon}), other(#{other_lat}, #{other_lon})"
        )
        return 0
      end

      distance_km = Geocoder::Calculations.distance_between(
        [current_lat, current_lon],
        [other_lat, other_lon],
        units: :km
      )

      # Check if Geocoder returned valid distance
      unless distance_km.finite?
        Rails.logger.warn(
          "Geocoder returned invalid distance (#{distance_km}) for points: " \
            "current(#{current_lat}, #{current_lon}), other(#{other_lat}, #{other_lon})"
        )
        return 0
      end

      result = (distance_km * 1000).to_f / ::DISTANCE_UNITS[unit.to_sym]

      # Final validation
      unless result.finite?
        Rails.logger.error "Final distance calculation resulted in invalid value (#{result})"
        return 0
      end

      result
    rescue StandardError => e
      Rails.logger.error "Error calculating distance from lonlat: #{e.message}"
      0
    end
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
