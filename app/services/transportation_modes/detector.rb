# frozen_string_literal: true

module TransportationModes
  # Orchestrates the detection pipeline for one track:
  # FeatureExtractor (SQL) -> Preprocessor -> Windower -> Decoder -> SegmentAssembler.
  # Never raises to callers — any failure degrades to a single unknown segment.
  #
  # Usage:
  #   TransportationModes::Detector.new(track, enabled_modes: [...], preserved: [...]).call
  #   # => array of segment hashes for TrackSegments::BulkInserter
  class Detector
    def initialize(track, enabled_modes: nil, preserved: [])
      @track = track
      @enabled_modes = (enabled_modes.presence || Track::TRANSPORTATION_MODES.keys).map(&:to_sym)
      @preserved = preserved
    end

    def call
      rows = Preprocessor.call(FeatureExtractor.call(@track.id))
      return default_unknown_segment if degenerate?(rows)

      windows = Windower.call(rows)
      return default_unknown_segment if windows.empty?

      decoded = Decoder.call(windows, enabled: @enabled_modes)
      SegmentAssembler.call(rows: rows, windows: windows, decoded: decoded, preserved: @preserved)
    rescue StandardError => e
      Rails.logger.error "[TransportationModes] track=#{@track.id} #{e.class}: #{e.message}"
      default_unknown_segment
    end

    private

    def degenerate?(rows)
      return true if rows.size < 2

      (rows.last[:ts] - rows.first[:ts]) < Emissions::TUNING[:min_track_duration_s]
    end

    def default_unknown_segment
      [
        {
          mode: :unknown,
          start_at: @track.start_at, end_at: @track.end_at,
          path_wkt: nil,
          distance: @track.distance&.to_i, duration: @track.duration,
          avg_speed: @track.avg_speed&.to_f, max_speed: nil,
          confidence: :low, confidence_score: 0.0,
          source: 'default'
        }
      ]
    end
  end
end
