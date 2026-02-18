# frozen_string_literal: true

module Users
  # Handles updating transportation threshold settings for a user.
  # Detects changes and triggers recalculation when needed.
  class TransportationThresholdsUpdater
    Result = Struct.new(:success?, :error, :recalculation_triggered?, keyword_init: true)

    THRESHOLD_KEYS = %w[transportation_thresholds transportation_expert_thresholds].freeze

    def initialize(user, settings_params)
      @user = user
      @settings_params = settings_params
      @old_thresholds = capture_current_thresholds
    end

    def call
      return locked_result if recalculation_in_progress?

      apply_settings
      return failure_result unless @user.save

      trigger_recalculation_if_needed
      success_result
    end

    private

    def recalculation_in_progress?
      return false unless threshold_params_present?

      status_manager.in_progress?
    end

    def capture_current_thresholds
      THRESHOLD_KEYS.index_with { |key| @user.settings[key]&.dup }
    end

    def apply_settings
      @settings_params.each do |key, value|
        next if key.to_s == 'timezone' && !ActiveSupport::TimeZone[value]

        @user.settings[key] = value
      end
    end

    def trigger_recalculation_if_needed
      return unless thresholds_changed?

      Tracks::TransportationModeRecalculationJob.perform_later(@user.id)
      @recalculation_triggered = true
    end

    def thresholds_changed?
      return false unless threshold_params_present?

      THRESHOLD_KEYS.any? do |key|
        @old_thresholds[key] != @user.settings[key]
      end
    end

    def threshold_params_present?
      THRESHOLD_KEYS.any? { |key| @settings_params.key?(key) || @settings_params.key?(key.to_sym) }
    end

    def status_manager
      @status_manager ||= Tracks::TransportationRecalculationStatus.new(@user.id)
    end

    def locked_result
      Result.new(
        success?: false,
        error: 'Transportation mode recalculation is in progress. Please wait until it completes.',
        recalculation_triggered?: false
      )
    end

    def failure_result
      Result.new(
        success?: false,
        error: @user.errors.full_messages.join(', '),
        recalculation_triggered?: false
      )
    end

    def success_result
      Result.new(
        success?: true,
        error: nil,
        recalculation_triggered?: @recalculation_triggered || false
      )
    end
  end
end
