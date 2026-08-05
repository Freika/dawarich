# frozen_string_literal: true

module TransportationModes
  # Reclassifies one track with the current detection pipeline. Idempotent:
  # auto segments are replaced, manually corrected segments preserved.
  class ReclassifyTrackJob < ApplicationJob
    queue_as :tracks
    sidekiq_options retry: 1

    def perform(track_id, report_progress: false)
      track = Track.find_by(id: track_id)
      return unless track

      reclassify(track)
      report(track) if report_progress
    end

    private

    def reclassify(track)
      Track.transaction do
        preserved = track.track_segments.manually_corrected.to_a
        track.track_segments.auto_classified.delete_all

        detector = Detector.new(
          track,
          enabled_modes: enabled_modes(track.user),
          preserved: preserved
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
      track.update_column(:dominant_mode, mode || :unknown)
    end

    def report(track)
      Tracks::TransportationRecalculationStatus.new(track.user_id).increment_processed!
    end
  end
end
