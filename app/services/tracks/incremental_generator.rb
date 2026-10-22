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
# 2. Segments by the user's time threshold, ignoring distance as in bulk generation
# 3. Creates tracks using the TrackBuilder module
# 4. Optionally merges new tracks with recent preceding tracks
#
# The lookback window is intentionally short to keep this fast. Untracked points
# after the user's latest track are handled by Tracks::DailyGenerationJob; older
# gaps between existing tracks need a manual track recalculation.
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
    Tracks::PerUserLock.with_user_lock(user.id) do
      segments = fetch_untracked_segments

      segments.each do |segment|
        next if segment[:points].size < 2

        track = create_track_from_points(
          segment[:points],
          segment[:pre_calculated_distance],
          tracker_id: segment[:tracker_id]
        )

        merge_with_recent_track(track) if track
      end

      Tracks::BoundaryDetector.new(user).resolve_cross_chunk_tracks
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
      untracked_only: true
    )
  end

  def lookback_start
    (Time.current - LOOKBACK_HOURS.hours).to_i
  end

  def time_threshold_minutes
    user.safe_settings.minutes_between_routes.to_i
  end

  def threshold_seconds
    time_threshold_minutes * 60
  end

  def merge_with_recent_track(new_track)
    end_preceding_track_at_arrival(new_track) if Tracks::StationaryStops.departure?(new_track, threshold_seconds)

    # Find a track that ended shortly before this one started
    # (within the time threshold, suggesting they're part of the same journey)
    preceding = user.tracks
                    .where(tracker_id: new_track.tracker_id)
                    .where('end_at < ?', new_track.start_at)
                    .where('end_at > ?', new_track.start_at - time_threshold_minutes.minutes)
                    .where.not(id: new_track.id)
                    .order(end_at: :desc)
                    .first

    return unless preceding

    Tracks::Merger.new(preceding, new_track).call
  end

  def end_preceding_track_at_arrival(departure_track)
    arrival_track = user.tracks
                        .where(tracker_id: departure_track.tracker_id)
                        .where('end_at < ?', departure_track.start_at)
                        .order(end_at: :desc)
                        .first
    return unless arrival_track

    dwell_ids = Tracks::StationaryStops.dwell_tail_point_ids(arrival_track, threshold_seconds)
    return if dwell_ids.empty?

    ActiveRecord::Base.transaction do
      Point.where(id: dwell_ids).update_all(track_id: nil)
      journey = arrival_track.points.order(:timestamp).to_a
      elevation = calculate_elevation_stats(journey)
      arrival_track.track_segments.auto_classified.delete_all
      arrival_track.update!(end_at: Time.zone.at(journey.last.timestamp),
                            elevation_gain: elevation[:gain], elevation_loss: elevation[:loss],
                            elevation_max: elevation[:max], elevation_min: elevation[:min])
    end
    begin
      detect_and_create_segments(arrival_track, arrival_track.points.order(:timestamp))
    rescue StandardError => e
      Rails.logger.error "Failed to detect segments after ending track #{arrival_track.id} at arrival: #{e.message}"
    end
  end
end
