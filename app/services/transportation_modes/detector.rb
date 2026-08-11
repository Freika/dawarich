# frozen_string_literal: true

module TransportationModes
  # Orchestrates the detection pipeline for one track:
  # FeatureExtractor (SQL) -> Preprocessor -> Windower -> Decoder -> SegmentAssembler.
  # With fallback (default), failures degrade to a single unknown segment;
  # with fallback: false, errors propagate so callers that replace existing
  # segments can roll back instead of committing a destructive overwrite.
  #
  # Usage:
  #   TransportationModes::Detector.new(track, enabled_modes: [...], preserved: [...]).call
  #   # => array of segment hashes for TrackSegments::BulkInserter
  class Detector
    def initialize(track, enabled_modes: nil, preserved: [], fallback: true)
      @track = track
      @enabled_modes = (enabled_modes.presence || Track::TRANSPORTATION_MODES.keys).map(&:to_sym)
      @preserved = preserved
      @fallback = fallback
    end

    def call
      rows = Preprocessor.call(FeatureExtractor.call(@track.id))
      return default_unknown_segment if degenerate?(rows)

      windows = Windower.call(rows)
      return default_unknown_segment if windows.empty?

      decoded = Decoder.call(windows, enabled: @enabled_modes)
      SegmentAssembler.call(rows: rows, windows: windows, decoded: decoded,
                            preserved: anchored_preserved)
    rescue StandardError => e
      ExceptionReporter.call(e, "Transportation mode detection failed for track #{@track.id}")
      raise unless @fallback

      default_unknown_segment
    end

    private

    # Legacy corrections may still be index-anchored (async backfill hasn't
    # reached their track). The assembler can only clip around time ranges,
    # so resolve them now — otherwise auto segments would overlap the
    # correction. Rows that cannot anchor (points gone) stay skipped.
    def anchored_preserved
      unanchored_ids = @preserved.select { |s| s.start_at.nil? && s.start_index.present? }.map(&:id)
      return @preserved if unanchored_ids.empty?

      TrackSegments::TimeAnchorBackfillJob.anchor_now(unanchored_ids)
      TrackSegment.where(id: @preserved.map(&:id)).to_a
    end

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
