# frozen_string_literal: true

# Optimization V1: LAG-based distance calculation with Ruby segmentation
# This keeps the existing Ruby segmentation logic but uses PostgreSQL LAG
# for batch distance calculations instead of individual queries

module OptimizedTracksV1
  extend ActiveSupport::Concern

  module ClassMethods
    # V1: Use LAG to get all consecutive distances in a single query
    def calculate_all_consecutive_distances(points)
      return [] if points.length < 2

      point_ids = points.map(&:id).join(',')
      
      results = connection.execute(<<-SQL.squish)
        WITH points_with_previous AS (
          SELECT
            id,
            timestamp,
            lonlat,
            LAG(lonlat) OVER (ORDER BY timestamp) as prev_lonlat,
            LAG(timestamp) OVER (ORDER BY timestamp) as prev_timestamp,
            LAG(id) OVER (ORDER BY timestamp) as prev_id
          FROM points 
          WHERE id IN (#{point_ids})
        )
        SELECT 
          id,
          prev_id,
          timestamp,
          prev_timestamp,
          ST_Distance(lonlat::geography, prev_lonlat::geography) as distance_meters,
          (timestamp - prev_timestamp) as time_diff_seconds
        FROM points_with_previous
        WHERE prev_lonlat IS NOT NULL
        ORDER BY timestamp
      SQL

      # Return hash mapping point_id => {distance_to_previous, time_diff}
      distance_map = {}
      results.each do |row|
        distance_map[row['id'].to_i] = {
          distance_meters: row['distance_meters'].to_f,
          time_diff_seconds: row['time_diff_seconds'].to_i,
          prev_id: row['prev_id'].to_i
        }
      end
      
      distance_map
    end

    # V1: Optimized total distance using LAG (already exists in distanceable.rb)
    def total_distance_lag(points, unit = :m)
      unless ::DISTANCE_UNITS.key?(unit.to_sym)
        raise ArgumentError, "Invalid unit. Supported units are: #{::DISTANCE_UNITS.keys.join(', ')}"
      end

      return 0 if points.length < 2

      point_ids = points.map(&:id).join(',')

      distance_in_meters = connection.select_value(<<-SQL.squish)
        WITH points_with_previous AS (
          SELECT
            lonlat,
            LAG(lonlat) OVER (ORDER BY timestamp) as prev_lonlat
          FROM points 
          WHERE id IN (#{point_ids})
        )
        SELECT COALESCE(
          SUM(ST_Distance(lonlat::geography, prev_lonlat::geography)),
          0
        )
        FROM points_with_previous
        WHERE prev_lonlat IS NOT NULL
      SQL

      distance_in_meters.to_f / ::DISTANCE_UNITS[unit.to_sym]
    end
  end
end

# Optimized segmentation module using pre-calculated distances
module OptimizedSegmentationV1
  extend ActiveSupport::Concern

  private

  def split_points_into_segments_v1(points)
    return [] if points.empty?

    # V1: Pre-calculate all distances and time diffs in one query
    if points.size > 1
      distance_data = Point.calculate_all_consecutive_distances(points)
    else
      distance_data = {}
    end

    segments = []
    current_segment = []

    points.each do |point|
      if current_segment.empty?
        # First point always starts a segment
        current_segment = [point]
      elsif should_start_new_segment_v1?(point, current_segment.last, distance_data)
        # Finalize current segment if it has enough points
        segments << current_segment if current_segment.size >= 2
        current_segment = [point]
      else
        current_segment << point
      end
    end

    # Don't forget the last segment
    segments << current_segment if current_segment.size >= 2

    segments
  end

  def should_start_new_segment_v1?(current_point, previous_point, distance_data)
    return false if previous_point.nil?

    # Get pre-calculated data for this point
    point_data = distance_data[current_point.id]
    return false unless point_data

    # Check time threshold
    time_threshold_seconds = time_threshold_minutes.to_i * 60
    return true if point_data[:time_diff_seconds] > time_threshold_seconds

    # Check distance threshold  
    distance_meters = point_data[:distance_meters]
    return true if distance_meters > distance_threshold_meters

    false
  end
end

# Add methods to Point class
class Point
  extend OptimizedTracksV1::ClassMethods
end