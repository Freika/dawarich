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

  # Sane upper bound for a single track's distance, in meters.
  # 100,000 km is roughly 2.5x Earth's circumference — anything beyond that points
  # to corrupt input rather than a real journey, so we cap and warn instead of
  # blindly storing it. The underlying column is bigint and could hold more,
  # but bad data is rarely useful.
  MAX_DISTANCE_METERS = 100_000_000

  def create_track_from_points(points, pre_calculated_distance, tracker_id: nil,
                               skip_segment_detection: false)
    return nil if points.size < 2

    resolved_tracker_id = tracker_id || points.first.tracker_id

    track = Track.new(
      user_id: user.id,
      tracker_id: resolved_tracker_id,
      start_at: Time.zone.at(points.first.timestamp),
      end_at: Time.zone.at(points.last.timestamp),
      original_path: build_path(points)
    )

    track.distance  = clamp_distance(pre_calculated_distance)
    track.duration  = calculate_duration(points)
    track.avg_speed = calculate_average_speed(track.distance, track.duration)

    # Calculate elevation statistics (no DB queries needed)
    elevation_stats = calculate_elevation_stats(points)
    track.elevation_gain = elevation_stats[:gain]
    track.elevation_loss = elevation_stats[:loss]
    track.elevation_max  = elevation_stats[:max]
    track.elevation_min  = elevation_stats[:min]

    saved_track = nil

    # `requires_new: true` forces a savepoint even when called from inside a
    # wrapping transaction (e.g. BoundaryDetector#merge_boundary_tracks). Without
    # it, a unique-violation on `track.save` aborts the outer transaction, and
    # subsequent queries (including the `find_by` in `reuse_existing_track`) fail
    # with InFailedSqlTransaction before the rescue path can run.
    ActiveRecord::Base.transaction(requires_new: true) do
      if track.save
        Point.where(id: points.map(&:id)).update_all(track_id: track.id)
        detect_and_create_segments(track, points) unless skip_segment_detection
        saved_track = track
      else
        Rails.logger.error "Failed to create track for user #{user.id}: #{track.errors.full_messages.join(', ')}"
      end
    end

    saved_track
  rescue ActiveRecord::RecordNotUnique => e
    reuse_existing_track(track, points, e)
  end

  def reuse_existing_track(track, points, original_error)
    existing = Track.find_by(user_id: user.id, start_at: track.start_at, end_at: track.end_at)

    unless existing
      # Under READ COMMITTED the conflicting row should be visible immediately
      # after RecordNotUnique. If we still can't find it, something is wrong
      # (replication lag, snapshot weirdness) — let the caller retry rather
      # than silently dropping the points from the user's timeline.
      Rails.logger.warn(
        "event=tracks.race_winner_not_visible user_id=#{user.id} " \
        "start_at=#{track.start_at} end_at=#{track.end_at}"
      )
      raise original_error
    end

    # Constrain reassignment to the winner's time window so we don't attach
    # points outside the existing track's start_at..end_at — the winner's
    # path/distance were computed from its own point set, and stretching it
    # silently corrupts the track's metadata. Points outside the window stay
    # orphaned (track_id: nil) and get picked up by the next generation pass.
    Point.where(
      id: points.map(&:id),
      track_id: nil,
      timestamp: existing.start_at.to_i..existing.end_at.to_i
    ).update_all(track_id: existing.id)

    Rails.logger.info(
      'event=tracks.unique_violation_rescued service=track_builder ' \
      "track_id=#{existing.id} user_id=#{user.id} " \
      "start_at=#{existing.start_at} end_at=#{existing.end_at}"
    )
    existing
  end

  def build_path(points)
    Tracks::BuildPath.new(points).call
  end

  def calculate_duration(points)
    points.last.timestamp - points.first.timestamp
  end

  def clamp_distance(raw_distance)
    rounded = raw_distance.to_f.round
    if rounded > MAX_DISTANCE_METERS
      Rails.logger.warn(
        "Track distance #{rounded}m exceeds maximum (#{MAX_DISTANCE_METERS}m); capping"
      )
      MAX_DISTANCE_METERS
    elsif rounded.negative?
      0
    else
      rounded
    end
  end

  def calculate_average_speed(distance_in_meters, duration_seconds)
    Track.avg_speed_kmh(distance_in_meters, duration_seconds)
  end

  def calculate_elevation_stats(points)
    altitudes = points.map(&:altitude).compact

    return default_elevation_stats if altitudes.empty?

    elevation_gain = 0
    elevation_loss = 0
    previous_altitude = altitudes.first

    altitudes[1..].each do |altitude|
      diff = altitude - previous_altitude
      if diff.positive?
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

  def detect_and_create_segments(track, _points)
    safe_settings = Users::SafeSettings.new(user.settings || {})
    detector = TransportationModes::Detector.new(
      track,
      enabled_modes: safe_settings.enabled_transportation_modes,
      preserved: track.track_segments.manually_corrected.to_a
    )
    segment_data = detector.call

    return if segment_data.empty?

    TrackSegments::BulkInserter.call(track, segment_data)
    update_dominant_mode(track, segment_data)
  rescue StandardError => e
    Rails.logger.error "Failed to detect transportation modes for track #{track.id}: #{e.message}"
  end

  def update_dominant_mode(track, segment_data)
    return if segment_data.empty?

    segments = segment_data.map do |d|
      TrackSegment.new(
        transportation_mode: d[:mode],
        distance: d[:distance],
        duration: d[:duration]
      )
    end
    mode = Track.pick_dominant_mode(segments)
    return unless mode

    # update_column skips after_commit, and dominant_mode is a tile property —
    # bump the epoch explicitly or reclassified tracks 304 with the old mode.
    track.update_column(:dominant_mode, mode)
    Tracks::TileEpoch.bump_range(track.user_id, track.start_at.to_i, track.end_at.to_i)
  end

  private

  def user
    raise NotImplementedError, 'Including class must implement user method'
  end
end
