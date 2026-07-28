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
      return invalid_allowlist_result if invalid_allowlist?

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

    def invalid_allowlist?
      raw = @settings_params['enabled_transportation_modes'] ||
            @settings_params[:enabled_transportation_modes]
      return false if raw.nil?

      valid = Track::TRANSPORTATION_MODES.keys.map(&:to_s)
      intersection = Array(raw).map(&:to_s) & valid
      Array(raw).any? && intersection.empty?
    end

    def invalid_allowlist_result
      Result.new(
        success?: false,
        error: 'Enable at least one transportation mode',
        recalculation_triggered?: false
      )
    end

    def capture_current_thresholds
      THRESHOLD_KEYS.index_with { |key| @user.settings[key]&.dup }
    end

    def apply_settings
      @settings_params.each do |key, value|
        next if key.to_s == 'timezone' && !ActiveSupport::TimeZone[value]

        if key.to_s == 'maps'
          merge_maps_settings(value)
        else
          @user.settings[key] = value
        end
      end

      sanitize_gated_layers if @user.plan_restricted?
    end

    # The `maps` hash also carries V1 keys (name, url, preferred_version)
    # managed by the settings page — merge instead of replacing so an API
    # update from the map panel can't clobber them.
    def merge_maps_settings(value)
      incoming = value.to_h
      incoming = incoming.except('hidden_tile_categories', 'disabled_poi_groups') if @user.plan_restricted?

      @user.settings['maps'] = (@user.settings['maps'] || {}).merge(incoming)
    end

    def sanitize_gated_layers
      if @user.settings.key?('enabled_map_layers')
        @user.settings['enabled_map_layers'] -= Users::SafeSettings::GATED_MAP_LAYERS
      end
      @user.settings['globe_projection'] = false if @settings_params.key?('globe_projection')
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
