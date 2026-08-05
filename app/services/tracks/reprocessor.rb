# frozen_string_literal: true

module Tracks
  # Reprocesses tracks to update transportation mode segments.
  # Can reprocess tracks for a specific import or individual tracks.
  #
  # Manually corrected segments are preserved: the Detector subtracts their
  # time ranges from the auto-classified output.
  class Reprocessor
    def initialize(import: nil, track: nil)
      @import = import
      @track = track
    end

    def reprocess_for_import
      return 0 unless @import

      track_ids = @import.points
                         .where.not(track_id: nil)
                         .distinct
                         .pluck(:track_id)

      return 0 if track_ids.empty?

      Rails.logger.info "Reprocessing #{track_ids.size} tracks for import #{@import.id}"

      count = 0
      Track.where(id: track_ids).includes(:user).find_each do |track|
        reprocess_track(track)
        count += 1
      end
      count
    end

    def reprocess_single
      return false unless @track

      reprocess_track(@track)
      true
    end

    def self.reprocess(track)
      new(track: track).reprocess_single
    end

    private

    def reprocess_track(track)
      Track.transaction do
        preserved = track.track_segments.manually_corrected.to_a
        track.track_segments.auto_classified.delete_all

        detector = TransportationModes::Detector.new(
          track,
          enabled_modes: extract_enabled_modes(track.user),
          preserved: preserved
        )
        create_segments(track, detector.call)
        recompute_dominant_mode(track)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to reprocess track #{track.id}: #{e.message}"
    end

    def extract_enabled_modes(user)
      return nil unless user

      Users::SafeSettings.new(user.settings || {}).enabled_transportation_modes
    end

    def create_segments(track, segment_data)
      return if segment_data.empty?

      TrackSegments::BulkInserter.call(track, segment_data)
    end

    def recompute_dominant_mode(track)
      all_segments = track.track_segments.reload.to_a
      return if all_segments.empty?

      mode = Track.pick_dominant_mode(all_segments)
      track.update!(dominant_mode: mode) if mode
    end
  end
end
