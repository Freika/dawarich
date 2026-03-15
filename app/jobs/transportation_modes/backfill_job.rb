# frozen_string_literal: true

module TransportationModes
  # Job to backfill transportation mode detection for existing tracks.
  # Processes tracks that don't have any track_segments or have unknown dominant_mode.
  #
  # Uses user-specific transportation thresholds from settings.
  #
  # Usage:
  #   TransportationModes::BackfillJob.perform_later(user_id)
  #   TransportationModes::BackfillJob.perform_later(user_id, batch_size: 50)
  #
  class BackfillJob < ApplicationJob
    queue_as :low_priority

    DEFAULT_BATCH_SIZE = 100

    def perform(user_id, batch_size: DEFAULT_BATCH_SIZE)
      @user = find_user_or_skip(user_id) || return

      # Extract user thresholds once for all tracks
      @user_thresholds, @expert_thresholds = extract_user_thresholds

      tracks_to_process.find_in_batches(batch_size: batch_size) do |tracks|
        tracks.each do |track|
          process_track(track)
        end
      end

      Rails.logger.info "Completed transportation mode backfill for user #{user_id}"
    end

    private

    def extract_user_thresholds
      safe_settings = Users::SafeSettings.new(@user.settings || {})
      [safe_settings.transportation_thresholds, safe_settings.transportation_expert_thresholds]
    end

    def tracks_to_process
      @user.tracks
           .left_joins(:track_segments)
           .where(track_segments: { id: nil })
           .or(@user.tracks.where(dominant_mode: :unknown))
           .distinct
           .order(created_at: :asc)
    end

    def process_track(track)
      points = track.points.order(:timestamp).to_a

      if points.size < 2
        track.update_column(:dominant_mode, :unknown)
        return
      end

      Track.transaction do
        track.track_segments.destroy_all

        detector = TransportationModes::Detector.new(
          track, points,
          user_thresholds: @user_thresholds,
          user_expert_thresholds: @expert_thresholds
        )
        segment_data = detector.call

        create_segments(track, segment_data)
      end

      Rails.logger.debug "Processed track #{track.id}: #{track.dominant_mode}"
    rescue StandardError => e
      Rails.logger.error "Failed to backfill track #{track.id}: #{e.message}"
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

      dominant_segment = segments.max_by { |s| s.duration || 0 }
      track.update_column(:dominant_mode, dominant_segment&.transportation_mode || :unknown)
    end
  end
end
