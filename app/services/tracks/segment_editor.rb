# frozen_string_literal: true

module Tracks
  class SegmentEditor
    Result = Struct.new(:success?, :segment, :track, :error_code, keyword_init: true)

    def initialize(segment, user)
      @segment = segment
      @user = user
    end

    def apply_override(mode)
      return failure(:mode_not_enabled) unless allows?(mode)

      @segment.transaction do
        @segment.update!(
          transportation_mode: mode,
          corrected_at: Time.current,
          confidence: :high,
          confidence_score: 1.0,
          source: 'user'
        )
        recompute_dominant_mode!
      end
      Result.new(success?: true, segment: @segment, track: @segment.track)
    end

    # Clearing a correction re-runs full detection for the track: per-segment
    # re-classification is meaningless in the windowed HMM pipeline. The
    # segment row is replaced by fresh auto-classified segments. One
    # transaction: a failed re-detection must not eat the manual correction.
    def reset_to_auto
      track = @segment.track
      Track.transaction do
        @segment.update!(corrected_at: nil, source: 'inferred')
        Tracks::Reprocessor.reprocess(track)
      end
      Result.new(success?: true, segment: nil, track: track.reload)
    rescue StandardError => e
      ExceptionReporter.call(e, "Failed to reset segment #{@segment.id} to auto")
      failure(:reprocess_failed)
    end

    private

    def failure(code)
      Result.new(success?: false, error_code: code)
    end

    def allows?(mode)
      Users::SafeSettings.new(@user.settings || {}).enabled_transportation_modes.include?(mode.to_s)
    end

    def recompute_dominant_mode!
      track = @segment.track
      segments = track.track_segments.reload.to_a
      return if segments.empty?

      mode = Track.pick_dominant_mode(segments)
      track.update!(dominant_mode: mode) if mode
    end
  end
end
