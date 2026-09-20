# frozen_string_literal: true

module TransportationModes
  # Reclassifies one track with the current detection pipeline. Idempotent:
  # auto segments are replaced, manually corrected segments preserved.
  class ReclassifyTrackJob < ApplicationJob
    queue_as :tracks
    sidekiq_options retry: 1

    def perform(track_id, report_progress: false, user_id: nil)
      track = Track.find_by(id: track_id)
      @report_user_id = user_id || track&.user_id
      reclassify(track) if track
    ensure
      # Progress must advance even on failure or a deleted track, or the
      # recalculation status never completes and mode settings stay locked
      # for the cache TTL. A retried failure may overshoot the counter;
      # complete is idempotent, so that only ends the progress display early.
      report if report_progress
    end

    private

    def reclassify(track)
      Track.transaction do
        preserved = track.track_segments.manually_corrected.to_a
        track.track_segments.auto_classified.delete_all

        detector = Detector.new(
          track,
          enabled_modes: enabled_modes(track.user),
          preserved: preserved,
          fallback: false
        )
        segment_data = detector.call
        TrackSegments::BulkInserter.call(track, segment_data) if segment_data.any?

        recompute_dominant_mode(track)
      end
    end

    def enabled_modes(user)
      return nil unless user

      Users::SafeSettings.new(user.settings || {}).enabled_transportation_modes
    end

    def recompute_dominant_mode(track)
      segments = track.track_segments.reload.to_a
      mode = segments.any? ? Track.pick_dominant_mode(segments) : :unknown
      # update_column skips after_commit, and dominant_mode is a tile property —
      # bump the epoch explicitly or reclassified tracks 304 with the old mode.
      track.update_column(:dominant_mode, mode || :unknown)
      Tracks::TileEpoch.bump_range(track.user_id, track.start_at.to_i, track.end_at.to_i)
    end

    def report
      return unless @report_user_id

      Tracks::TransportationRecalculationStatus.new(@report_user_id).increment_processed!
    end
  end
end
