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
    # Minimum track duration in seconds to attempt detection
    # Very short tracks (< 30 seconds) default to unknown
    MIN_TRACK_DURATION = 30

    # Minimum number of points required for meaningful detection
    MIN_POINTS = 2

    def initialize(track, points)
      @track = track
      @points = points.sort_by(&:timestamp)
    end

    def call
      return default_unknown_segment if skip_detection?

      # 1. Try to extract activity data from source (Overland, Google, etc.)
      source_segments = extract_source_activity_data
      return source_segments if source_segments.present?

      # 2. Fall back to movement-based inference (speed + acceleration)
      infer_segments_from_movement
    end

    private

    attr_reader :track, :points

    def skip_detection?
      return true if points.size < MIN_POINTS

      duration = points.last.timestamp - points.first.timestamp
      duration < MIN_TRACK_DURATION
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
