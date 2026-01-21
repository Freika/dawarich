# frozen_string_literal: true

module Tracks
  # Reprocesses tracks to update transportation mode segments.
  # Can reprocess tracks for a specific import or individual tracks.
  class Reprocessor
    def initialize(import: nil, track: nil)
      @import = import
      @track = track
    end

    # Reprocess all tracks associated with an import
    def reprocess_for_import
      return 0 unless @import

      track_ids = @import.points
                         .where.not(track_id: nil)
                         .distinct
                         .pluck(:track_id)

      return 0 if track_ids.empty?

      Rails.logger.info "Reprocessing #{track_ids.size} tracks for import #{@import.id}"

      count = 0
      Track.where(id: track_ids).find_each do |track|
        reprocess_track(track)
        count += 1
      end
      count
    end

    # Reprocess a single track
    def reprocess_single
      return false unless @track

      reprocess_track(@track)
      true
    end

    # Class method for convenience
    def self.reprocess(track)
      new(track: track).reprocess_single
    end

    private

    def reprocess_track(track)
      points = track.points.order(:timestamp).to_a
      return if points.size < 2

      # Clear existing segments
      track.track_segments.destroy_all

      # Re-detect transportation modes and create segments
      detector = TransportationModes::Detector.new(track, points)
      segment_data = detector.call

      create_segments(track, segment_data)
    rescue StandardError => e
      Rails.logger.error "Failed to reprocess track #{track.id}: #{e.message}"
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
      end.compact

      update_dominant_mode(track, segments)
    end

    def update_dominant_mode(track, segments)
      return if segments.empty?

      dominant_segment = segments.max_by { |s| s.duration || 0 }
      return unless dominant_segment

      track.update_column(:dominant_mode, dominant_segment.transportation_mode)
    end
  end
end
