# frozen_string_literal: true

# Track segmentation logic for splitting GPS points into meaningful track segments.
#
# This module provides the core algorithm for determining where one track ends
# and another begins, based on time gaps and distance jumps between consecutive points.
#
# How it works:
# 1. Analyzes consecutive GPS points to detect gaps that indicate separate journeys
# 2. Uses configurable time and distance thresholds to identify segment boundaries
# 3. Splits large arrays of points into smaller arrays representing individual tracks
# 4. Provides utilities for handling both Point objects and hash representations
#
# Segmentation criteria:
# - Time threshold: Gap longer than X minutes indicates a new track
# - Distance threshold: Jump larger than X meters indicates a new track
# - Minimum segment size: Segments must have at least 2 points to form a track
#
# The module is designed to be included in classes that need segmentation logic
# and requires the including class to implement distance_threshold_meters and
# time_threshold_minutes methods.
#
# Used by:
# - Tracks::Generator for splitting points during track generation
# - Tracks::CreateFromPoints for legacy compatibility
#
# Example usage:
#   class MyTrackProcessor
#     include Tracks::Segmentation
#
#     def distance_threshold_meters; 500; end
#     def time_threshold_minutes; 60; end
#
#     def process_points(points)
#       segments = split_points_into_segments(points)
#       # Process each segment...
#     end
#   end
#
module Tracks::Segmentation
  extend ActiveSupport::Concern

  private

  def split_points_into_segments(points)
    return [] if points.empty?

    segments = []
    current_segment = []

    points.each do |point|
      if should_start_new_segment?(point, current_segment.last)
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

  def should_start_new_segment?(current_point, previous_point)
    return false if previous_point.nil?

    # Check time threshold (convert minutes to seconds)
    current_timestamp = point_timestamp(current_point)
    previous_timestamp = point_timestamp(previous_point)

    time_diff_seconds = current_timestamp - previous_timestamp
    time_threshold_seconds = time_threshold_minutes.to_i * 60

    return true if time_diff_seconds > time_threshold_seconds

    # Check distance threshold - convert km to meters to match frontend logic
    distance_km = calculate_distance_kilometers_between_points(previous_point, current_point)
    distance_meters = distance_km * 1000 # Convert km to meters
    return true if distance_meters > distance_threshold_meters

    false
  end

  def calculate_distance_kilometers_between_points(point1, point2)
    lat1, lon1 = point_coordinates(point1)
    lat2, lon2 = point_coordinates(point2)

    # Use Geocoder to match behavior with frontend (same library used elsewhere in app)
    Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km)
  end

  def should_finalize_segment?(segment_points, grace_period_minutes = 5)
    return false if segment_points.size < 2

    last_point = segment_points.last
    last_timestamp = point_timestamp(last_point)
    current_time = Time.current.to_i

    # Don't finalize if the last point is too recent (within grace period)
    time_since_last_point = current_time - last_timestamp
    grace_period_seconds = grace_period_minutes * 60

    time_since_last_point > grace_period_seconds
  end

  def point_timestamp(point)
    if point.respond_to?(:timestamp)
      # Point objects from database always have integer timestamps
      point.timestamp
    elsif point.is_a?(Hash)
      # Hash might come from Redis buffer or test data
      timestamp = point[:timestamp] || point['timestamp']
      timestamp.to_i
    else
      raise ArgumentError, "Invalid point type: #{point.class}"
    end
  end

  def point_coordinates(point)
    if point.respond_to?(:lat) && point.respond_to?(:lon)
      [point.lat, point.lon]
    elsif point.is_a?(Hash)
      [point[:lat] || point['lat'], point[:lon] || point['lon']]
    else
      raise ArgumentError, "Invalid point type: #{point.class}"
    end
  end

  # These methods need to be implemented by the including class
  def distance_threshold_meters
    raise NotImplementedError, "Including class must implement distance_threshold_meters"
  end

  def time_threshold_minutes
    raise NotImplementedError, "Including class must implement time_threshold_minutes"
  end
end
