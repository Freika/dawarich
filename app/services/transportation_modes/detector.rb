# frozen_string_literal: true

module TransportationModes
  # Main orchestrator for transportation mode detection.
  # Tries source-provided activity data first, then falls back to inference.
  #
  # Usage:
  #   detector = TransportationModes::Detector.new(track, points)
  #   segment_data = detector.call
  #   # Returns array of hashes with segment data ready for TrackSegment creation
  #
  class Detector
    MIN_TRACK_DURATION_SECONDS = 30
    MIN_POINTS = 2

    def initialize(track, points)
      @track = track
      @points = points.sort_by(&:timestamp)
    end

    def call
      return default_unknown_segment if skip_detection?

      source_segments = extract_source_activity_data
      return source_segments if source_segments.present?

      infer_segments_from_movement
    end

    private

    attr_reader :track, :points

    def skip_detection?
      return true if points.size < MIN_POINTS

      duration = points.last.timestamp - points.first.timestamp
      duration < MIN_TRACK_DURATION_SECONDS
    end

    def default_unknown_segment
      [
        {
          mode: :unknown,
          start_index: 0,
          end_index: [points.size - 1, 0].max,
          distance: track.distance&.to_i,
          duration: track.duration,
          avg_speed: track.avg_speed,
          max_speed: nil,
          avg_acceleration: nil,
          confidence: :low,
          source: 'default'
        }
      ]
    end

    def extract_source_activity_data
      SourceDataExtractor.new(points).call
    end

    def infer_segments_from_movement
      MovementAnalyzer.new(track, points).call
    end
  end
end
