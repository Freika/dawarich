# frozen_string_literal: true

# Track creation and statistics calculation module for building Track records from GPS points.
#
# This module provides the core functionality for converting arrays of GPS points into
# Track database records with calculated statistics including distance, duration, speed,
# and elevation metrics.
#
# How it works:
# 1. Takes an array of Point objects representing a track segment
# 2. Creates a Track record with basic temporal and spatial boundaries
# 3. Calculates comprehensive statistics: distance, duration, average speed
# 4. Computes elevation metrics: gain, loss, maximum, minimum
# 5. Builds a LineString path representation for mapping
# 6. Associates all points with the created track
#
# Statistics calculated:
# - Distance: Always stored in meters as integers for consistency
# - Duration: Total time in seconds between first and last point
# - Average speed: In km/h regardless of user's distance unit preference
# - Elevation gain/loss: Cumulative ascent and descent in meters
# - Elevation max/min: Highest and lowest altitudes in the track
#
# Distance is converted to user's preferred unit only at display time, not storage time.
# This ensures consistency when users change their distance unit preferences.
#
# Used by:
# - Tracks::ParallelGenerator and related jobs for creating tracks during parallel generation
# - Any class that needs to convert point arrays to Track records
#
# Example usage:
#   class MyTrackProcessor
#     include Tracks::TrackBuilder
#
#     def initialize(user)
#       @user = user
#     end
#
#     def process_segment(points)
#       track = create_track_from_points(points)
#       # Track now exists with calculated statistics
#     end
#
#     private
#
#     attr_reader :user
#   end
#
module Tracks::TrackBuilder
  extend ActiveSupport::Concern

  def create_track_from_points(points, pre_calculated_distance)
    return nil if points.size < 2

    track = Track.new(
      user_id: user.id,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp),
      original_path: build_path(points)
    )

    # TODO: Move trips attrs to columns with more precision and range
    track.distance  = [[pre_calculated_distance.round, 999_999.99].min, 0].max
    track.duration  = calculate_duration(points)
    track.avg_speed = calculate_average_speed(track.distance, track.duration)

    # Calculate elevation statistics (no DB queries needed)
    elevation_stats = calculate_elevation_stats(points)
    track.elevation_gain = elevation_stats[:gain]
    track.elevation_loss = elevation_stats[:loss]
    track.elevation_max  = elevation_stats[:max]
    track.elevation_min  = elevation_stats[:min]

    if track.save
      Point.where(id: points.map(&:id)).update_all(track_id: track.id)

      track
    else
      Rails.logger.error "Failed to create track for user #{user.id}: #{track.errors.full_messages.join(', ')}"
      nil
    end
  end

  def build_path(points)
    Tracks::BuildPath.new(points).call
  end

  def calculate_track_distance(points)
    # Always calculate and store distance in meters for consistency
    distance_in_meters = Point.total_distance(points, :m)
    distance_in_meters.round
  end

  def calculate_duration(points)
    points.last.timestamp - points.first.timestamp
  end

  def calculate_average_speed(distance_in_meters, duration_seconds)
    return 0.0 if duration_seconds <= 0 || distance_in_meters <= 0

    # Speed in meters per second, then convert to km/h for storage
    speed_mps = distance_in_meters.to_f / duration_seconds
    speed_kmh = (speed_mps * 3.6).round(2) # m/s to km/h

    # Cap the speed to prevent database precision overflow (max 999999.99)
    [speed_kmh, 999_999.99].min
  end

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

  def default_elevation_stats
    {
      gain: 0,
      loss: 0,
      max: 0,
      min: 0
    }
  end

  private

  def user
    raise NotImplementedError, 'Including class must implement user method'
  end
end
