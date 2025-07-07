# frozen_string_literal: true

module Tracks::TrackBuilder
  extend ActiveSupport::Concern

  # Create a track from an array of points
  # @param points [Array<Point>] array of Point objects
  # @return [Track, nil] created track or nil if creation failed
  def create_track_from_points(points)
    return nil if points.size < 2

    track = Track.new(
      user_id: user.id,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp),
      original_path: build_path(points)
    )

    # Calculate track statistics
    track.distance = calculate_track_distance(points)
    track.duration = calculate_duration(points)
    track.avg_speed = calculate_average_speed(track.distance, track.duration)

    # Calculate elevation statistics
    elevation_stats = calculate_elevation_stats(points)
    track.elevation_gain = elevation_stats[:gain]
    track.elevation_loss = elevation_stats[:loss]
    track.elevation_max = elevation_stats[:max]
    track.elevation_min = elevation_stats[:min]

    if track.save!
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)
      track
    else
      Rails.logger.error "Failed to create track for user #{user.id}: #{track.errors.full_messages.join(', ')}"
      nil
    end
  end

  # Build path from points using existing BuildPath service
  # @param points [Array<Point>] array of Point objects
  # @return [String] LineString representation of the path
  def build_path(points)
    Tracks::BuildPath.new(points.map(&:lonlat)).call
  end

  # Calculate track distance in meters for storage
  # @param points [Array<Point>] array of Point objects
  # @return [Integer] distance in meters
  def calculate_track_distance(points)
    distance_in_user_unit = Point.total_distance(points, user.safe_settings.distance_unit || 'km')

    # Convert to meters for storage (Track model expects distance in meters)
    case user.safe_settings.distance_unit
    when 'miles', 'mi'
      (distance_in_user_unit * 1609.344).round # miles to meters
    else
      (distance_in_user_unit * 1000).round # km to meters
    end
  end

  # Calculate track duration in seconds
  # @param points [Array<Point>] array of Point objects
  # @return [Integer] duration in seconds
  def calculate_duration(points)
    points.last.timestamp - points.first.timestamp
  end

  # Calculate average speed in km/h
  # @param distance_meters [Numeric] distance in meters
  # @param duration_seconds [Numeric] duration in seconds
  # @return [Float] average speed in km/h
  def calculate_average_speed(distance_meters, duration_seconds)
    return 0.0 if duration_seconds <= 0 || distance_meters <= 0

    # Speed in meters per second, then convert to km/h for storage
    speed_mps = distance_meters.to_f / duration_seconds
    (speed_mps * 3.6).round(2) # m/s to km/h
  end

  # Calculate elevation statistics from points
  # @param points [Array<Point>] array of Point objects
  # @return [Hash] elevation statistics hash
  def calculate_elevation_stats(points)
    altitudes = points.map(&:altitude).compact

    return default_elevation_stats if altitudes.empty?

    elevation_gain = 0
    elevation_loss = 0
    previous_altitude = altitudes.first

    altitudes[1..].each do |altitude|
      diff = altitude - previous_altitude
      if diff > 0
        elevation_gain += diff
      else
        elevation_loss += diff.abs
      end
      previous_altitude = altitude
    end

    {
      gain: elevation_gain.round,
      loss: elevation_loss.round,
      max: altitudes.max,
      min: altitudes.min
    }
  end

  # Default elevation statistics when no altitude data is available
  # @return [Hash] default elevation statistics
  def default_elevation_stats
    {
      gain: 0,
      loss: 0,
      max: 0,
      min: 0
    }
  end

  private

  # This method must be implemented by the including class
  # @return [User] the user for which tracks are being created
  def user
    raise NotImplementedError, "Including class must implement user method"
  end
end
