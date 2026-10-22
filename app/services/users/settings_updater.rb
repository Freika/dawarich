# frozen_string_literal: true

module Users
  # Applies user settings updates from the API: plan-gated sanitization,
  # allowlist validation, and reclassification when the transportation mode
  # allowlist changes (the former threshold settings are gone — the detection
  # pipeline tunes itself).
  class SettingsUpdater
    Result = Struct.new(:success?, :error, :recalculation_triggered?, keyword_init: true)

    MODES_KEY = 'enabled_transportation_modes'
    CITY_THRESHOLD_KEY = 'min_minutes_spent_in_city'
    SUPPORTER_KEY = 'app_store_supporter'
    SUPPORTER_INSTALL_KEY = 'app_store_supporter_install'
    SUPPORTER_INSTALLS_KEY = 'app_store_supporter_installs'
    MAX_INSTALL_ID_LENGTH = 128

    def initialize(user, settings_params)
      @user = user
      @settings_params = settings_params
      @old_enabled_modes = user.settings_hash[MODES_KEY]&.dup
      @old_city_threshold = normalized_city_threshold(user.settings_hash[CITY_THRESHOLD_KEY])
    end

    def call
      unless @user.settings.is_a?(Hash)
        @user.errors.add(:settings, :invalid)
        return failure_result
      end
      return locked_result if recalculation_in_progress?
      return invalid_allowlist_result if invalid_allowlist?

      apply_settings
      return failure_result unless @user.save

      trigger_recalculation_if_needed
      success_result
    end

    private

    def recalculation_in_progress?
      return false unless modes_param_present?

      status_manager.in_progress?
    end

    def modes_param_present?
      @settings_params.key?(MODES_KEY) || @settings_params.key?(MODES_KEY.to_sym)
    end

    def invalid_allowlist?
      raw = @settings_params[MODES_KEY] || @settings_params[MODES_KEY.to_sym]
      return false if raw.nil?

      valid = Track::TRANSPORTATION_MODES.keys.map(&:to_s)
      intersection = Array(raw).map(&:to_s) & valid
      Array(raw).any? && intersection.empty?
    end

    def invalid_allowlist_result
      Result.new(
        success?: false,
        error: I18n.t('services.users.settings_updater.enable_at_least_one_transportation_mode'),
        recalculation_triggered?: false
      )
    end

    def apply_settings
      @settings_params.each do |key, value|
        next if key.to_s == 'timezone' && !ActiveSupport::TimeZone[value]
        next if key.to_s == SUPPORTER_INSTALL_KEY

        if key.to_s == 'maps'
          merge_maps_settings(value)
        elsif key.to_s == SUPPORTER_KEY
          apply_supporter_flag(value)
        else
          @user.settings[key] = value
        end
      end

      sanitize_gated_layers if @user.plan_restricted?
    end

    # The `maps` hash may still carry legacy Map v1 keys (name, url,
    # preferred_version) on existing accounts — merge instead of replacing
    # so an API update from the map panel can't clobber other keys.
    def merge_maps_settings(value)
      incoming = value.to_h
      incoming = incoming.except('hidden_tile_categories', 'disabled_poi_groups') if @user.plan_restricted?

      @user.settings['maps'] = (@user.settings['maps'] || {}).merge(incoming)
    end

    def apply_supporter_flag(value)
      install = supporter_install_id
      return @user.settings[SUPPORTER_KEY] = value if install.nil?

      installs = Array(@user.settings[SUPPORTER_INSTALLS_KEY]) - [install]
      installs << install if ActiveModel::Type::Boolean.new.cast(value)
      @user.settings[SUPPORTER_INSTALLS_KEY] = installs
      @user.settings[SUPPORTER_KEY] = installs.any?
    end

    def supporter_install_id
      raw = @settings_params[SUPPORTER_INSTALL_KEY] || @settings_params[SUPPORTER_INSTALL_KEY.to_sym]
      return unless raw.is_a?(String)

      id = raw.strip
      id if id.present? && id.length <= MAX_INSTALL_ID_LENGTH
    end

    def sanitize_gated_layers
      if @user.settings.key?('enabled_map_layers')
        @user.settings['enabled_map_layers'] -= Users::SafeSettings::GATED_MAP_LAYERS
      end
      @user.settings['globe_projection'] = false if @settings_params.key?('globe_projection')
    end

    def trigger_recalculation_if_needed
      trigger_mode_reclassification
      trigger_city_stats_recalculation
    end

    def trigger_mode_reclassification
      return unless modes_param_present?
      return if @old_enabled_modes == @user.settings_hash[MODES_KEY]

      TransportationModes::UserReclassifyJob.perform_later(@user.id)
      @recalculation_triggered = true
    end

    def trigger_city_stats_recalculation
      return unless city_threshold_param_present?
      return if @old_city_threshold == normalized_city_threshold(@user.settings_hash[CITY_THRESHOLD_KEY])

      Stats::RecalculationDebouncer.new(@user.id).trigger
      Achievements::CheckJob.schedule(@user.id)
      @recalculation_triggered = true
    end

    def city_threshold_param_present?
      @settings_params.key?(CITY_THRESHOLD_KEY) || @settings_params.key?(CITY_THRESHOLD_KEY.to_sym)
    end

    def normalized_city_threshold(value)
      (value || Users::SafeSettings::DEFAULT_VALUES[CITY_THRESHOLD_KEY]).to_i
    end

    def status_manager
      @status_manager ||= Tracks::TransportationRecalculationStatus.new(@user.id)
    end

    def locked_result
      Result.new(
        success?: false,
        error: I18n.t('services.users.settings_updater.recalculation_in_progress'),
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
