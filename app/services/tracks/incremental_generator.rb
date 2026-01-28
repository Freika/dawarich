# frozen_string_literal: true

# Lightweight track generator for near real-time track creation.
#
# This service is optimized for processing small batches of recent points
# (typically from the last few hours) rather than bulk historical data.
# It leverages the existing SQL-based segmentation in Track.get_segments_with_points
# for efficient point grouping and track creation.
#
# How it works:
# 1. Queries for untracked points within the lookback window (default: 6 hours)
# 2. Uses SQL-based segmentation with user's time/distance thresholds
# 3. Creates tracks using the TrackBuilder module
# 4. Optionally merges new tracks with recent preceding tracks
#
# The lookback window is intentionally short to keep this fast. Older untracked
# points are handled by the daily generation job (Tracks::DailyGenerationJob).
#
# Used by:
# - Tracks::RealtimeGenerationJob
#
class Tracks::IncrementalGenerator
  include Tracks::TrackBuilder

  LOOKBACK_HOURS = 6

  def initialize(user)
    @user = user
  end

  def call
    segments = fetch_untracked_segments
    return if segments.empty?

    segments.each do |segment|
      next if segment[:points].size < 2

      track = create_track_from_points(
        segment[:points],
        segment[:pre_calculated_distance]
      )

      merge_with_recent_track(track) if track
    end
  end

  private

  attr_reader :user

  def fetch_untracked_segments
    Track.get_segments_with_points(
      user.id,
      lookback_start,
      Time.current.to_i,
      time_threshold_minutes,
      distance_threshold_meters,
      untracked_only: true
    )
  end

  def lookback_start
    (Time.current - LOOKBACK_HOURS.hours).to_i
  end

  def time_threshold_minutes
    user.safe_settings.minutes_between_routes.to_i
  end

  def distance_threshold_meters
    user.safe_settings.meters_between_routes.to_i
  end

  def merge_with_recent_track(new_track)
    # Find a track that ended shortly before this one started
    # (within the time threshold, suggesting they're part of the same journey)
    preceding = user.tracks
                    .where('end_at < ?', new_track.start_at)
                    .where('end_at > ?', new_track.start_at - time_threshold_minutes.minutes)
                    .where.not(id: new_track.id)
                    .order(end_at: :desc)
                    .first

    return unless preceding

    Tracks::Merger.new(preceding, new_track).call
  end
end
