# frozen_string_literal: true

module Tracks
  # Reprocesses tracks to update transportation mode segments.
  # Can reprocess tracks for a specific import or individual tracks.
  #
  # Uses user-specific transportation thresholds from settings when available.
  class Reprocessor
    LARGE_TRACK_THRESHOLD = 10_000

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
      points_count = track.points.count
      return if points_count < 2

      if points_count > LARGE_TRACK_THRESHOLD
        Rails.logger.warn "[Reprocessor] Track #{track.id} has #{points_count} points, " \
                          "which may use significant memory during reprocessing"
      end

      points = track.points.order(:timestamp).to_a

      Track.transaction do
        track.track_segments.destroy_all

        # Get user-specific thresholds
        user_thresholds, expert_thresholds = extract_user_thresholds(track.user)

        detector = TransportationModes::Detector.new(
          track, points,
          user_thresholds: user_thresholds,
          user_expert_thresholds: expert_thresholds
        )
        segment_data = detector.call

        create_segments(track, segment_data)
      end
    rescue StandardError => e
      Rails.logger.error "Failed to reprocess track #{track.id}: #{e.message}"
    end

    def extract_user_thresholds(user)
      return [nil, nil] unless user

      safe_settings = Users::SafeSettings.new(user.settings || {})
      [safe_settings.transportation_thresholds, safe_settings.transportation_expert_thresholds]
    end

    def create_segments(track, segment_data)
      return if segment_data.empty?

      segments = segment_data.map do |data|
        track.track_segments.create(
          transportation_mode: data[:mode],
          start_index: data[:start_index],
          end_index: data[:end_index],
          distance: data[:distance],
          duration: data[:duration],
          avg_speed: data[:avg_speed],
          max_speed: data[:max_speed],
          avg_acceleration: data[:avg_acceleration],
          confidence: data[:confidence],
          source: data[:source]
        )
      end.select(&:persisted?)

      update_dominant_mode(track, segments)
    end

    def update_dominant_mode(track, segments)
      return if segments.empty?

      dominant_segment = segments.max_by { |s| s.duration || 0 }
      return unless dominant_segment

      track.update(dominant_mode: dominant_segment.transportation_mode)
    end
  end
end
