# frozen_string_literal: true

module Tracks
  class SegmentEditor
    Result = Struct.new(:success?, :segment, :error_code, keyword_init: true)

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
          source: 'user'
        )
        recompute_dominant_mode!
      end
      success
    end

    def reset_to_auto
      @segment.transaction do
        classifier = TransportationModes::ModeClassifier.new(
          avg_speed_kmh: @segment.avg_speed,
          max_speed_kmh: @segment.max_speed,
          avg_acceleration: @segment.avg_acceleration,
          duration: @segment.duration,
          user_thresholds: safe_settings.transportation_thresholds,
          user_expert_thresholds: safe_settings.transportation_expert_thresholds,
          enabled_modes: safe_settings.enabled_transportation_modes
        )
        @segment.update!(
          transportation_mode: classifier.classify,
          confidence: classifier.confidence,
          corrected_at: nil,
          source: 'gps'
        )
        recompute_dominant_mode!
      end
      success
    end

    private

    def safe_settings
      @safe_settings ||= Users::SafeSettings.new(@user.settings || {})
    end

    def allows?(mode)
      safe_settings.enabled_transportation_modes.include?(mode.to_s)
    end

    def recompute_dominant_mode!
      track = @segment.track
      segments = track.track_segments.reload.to_a
      return if segments.empty?

      dominant = segments.max_by { |s| s.duration || 0 }
      track.update(dominant_mode: dominant.transportation_mode)
    end

    def success
      Result.new(success?: true, segment: @segment)
    end

    def failure(code)
      Result.new(success?: false, error_code: code)
    end
  end
end
