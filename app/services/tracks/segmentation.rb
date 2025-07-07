# frozen_string_literal: true

module Tracks::Segmentation
  extend ActiveSupport::Concern

  private

  # Split an array of points into track segments based on time and distance thresholds
  # @param points [Array] array of Point objects or point hashes
  # @return [Array<Array>] array of point segments
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

  # Check if a new segment should start based on time and distance thresholds
  # @param current_point [Point, Hash] current point (Point object or hash)
  # @param previous_point [Point, Hash, nil] previous point or nil
  # @return [Boolean] true if new segment should start
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

  # Calculate distance between two points in kilometers
  # @param point1 [Point, Hash] first point
  # @param point2 [Point, Hash] second point
  # @return [Float] distance in kilometers
  def calculate_distance_kilometers_between_points(point1, point2)
    lat1, lon1 = point_coordinates(point1)
    lat2, lon2 = point_coordinates(point2)

    # Use Geocoder to match behavior with frontend (same library used elsewhere in app)
    Geocoder::Calculations.distance_between([lat1, lon1], [lat2, lon2], units: :km)
  end

  # Check if a segment should be finalized (has a large enough gap at the end)
  # @param segment_points [Array] array of points in the segment
  # @param grace_period_minutes [Integer] grace period in minutes (default 5)
  # @return [Boolean] true if segment should be finalized
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

  # Extract timestamp from point (handles both Point objects and hashes)
  # @param point [Point, Hash] point object or hash
  # @return [Integer] timestamp as integer
  def point_timestamp(point)
    if point.respond_to?(:timestamp)
      point.timestamp
    elsif point.is_a?(Hash)
      point[:timestamp] || point['timestamp']
    else
      raise ArgumentError, "Invalid point type: #{point.class}"
    end
  end

  # Extract coordinates from point (handles both Point objects and hashes)
  # @param point [Point, Hash] point object or hash
  # @return [Array<Float>] [lat, lon] coordinates
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
