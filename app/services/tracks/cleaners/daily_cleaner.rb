# frozen_string_literal: true

# Track cleaning strategy for daily track processing.
#
# This cleaner handles tracks that overlap with the specified time window,
# ensuring proper handling of cross-day tracks and preventing orphaned points.
#
# How it works:
# 1. Finds tracks that overlap with the time window (not just those completely contained)
# 2. For overlapping tracks, removes only points within the time window
# 3. Deletes tracks that become empty after point removal
# 4. Preserves tracks that extend beyond the time window with their remaining points
#
# Key differences from ReplaceCleaner:
# - Handles tracks that span multiple days correctly
# - Uses overlap logic instead of containment logic
# - Preserves track portions outside the processing window
# - Prevents orphaned points from cross-day tracks
#
# Used primarily for:
# - Daily track processing that handles 24-hour windows
# - Incremental processing that respects existing cross-day tracks
# - Scenarios where tracks may span the processing boundary
#
# Example usage:
#   cleaner = Tracks::Cleaners::DailyCleaner.new(user, start_at: 1.day.ago.beginning_of_day, end_at: 1.day.ago.end_of_day)
#   cleaner.cleanup
#
module Tracks
  module Cleaners
    class DailyCleaner
      attr_reader :user, :start_at, :end_at

      def initialize(user, start_at: nil, end_at: nil)
        @user = user
        @start_at = start_at
        @end_at = end_at
      end

      def cleanup
        return unless start_at.present? && end_at.present?

        overlapping_tracks = find_overlapping_tracks

        return if overlapping_tracks.empty?

        Rails.logger.info "Processing #{overlapping_tracks.count} overlapping tracks for user #{user.id} in time window #{start_at} to #{end_at}"

        overlapping_tracks.each do |track|
          process_overlapping_track(track)
        end
      end

      private

      def find_overlapping_tracks
        # Find tracks that overlap with our time window
        # A track overlaps if: track_start < window_end AND track_end > window_start
        user.tracks.where(
          '(start_at < ? AND end_at > ?)',
          Time.zone.at(end_at),
          Time.zone.at(start_at)
        )
      end

      def process_overlapping_track(track)
        # Find points within our time window that belong to this track
        points_in_window = track.points.where(
          'timestamp >= ? AND timestamp <= ?',
          start_at.to_i,
          end_at.to_i
        )

        if points_in_window.empty?
          Rails.logger.debug "Track #{track.id} has no points in time window, skipping"
          return
        end

        # Remove these points from the track
        points_in_window.update_all(track_id: nil)

        Rails.logger.debug "Removed #{points_in_window.count} points from track #{track.id}"

        # Check if the track has any remaining points
        remaining_points_count = track.points.count

        if remaining_points_count == 0
          # Track is now empty, delete it
          Rails.logger.debug "Track #{track.id} is now empty, deleting"
          track.destroy!
        elsif remaining_points_count < 2
          # Track has too few points to be valid, delete it and orphan remaining points
          Rails.logger.debug "Track #{track.id} has insufficient points (#{remaining_points_count}), deleting"
          track.points.update_all(track_id: nil)
          track.destroy!
        else
          # Track still has valid points outside our window, update its boundaries
          Rails.logger.debug "Track #{track.id} still has #{remaining_points_count} points, updating boundaries"
          update_track_boundaries(track)
        end
      end

      def update_track_boundaries(track)
        remaining_points = track.points.order(:timestamp)

        return if remaining_points.empty?

        # Update track start/end times based on remaining points
        track.update!(
          start_at: Time.zone.at(remaining_points.first.timestamp),
          end_at: Time.zone.at(remaining_points.last.timestamp)
        )
      end
    end
  end
end
