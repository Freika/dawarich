# frozen_string_literal: true

module Users
  # Restores map look settings to their defaults by deleting the stored values,
  # so the account matches a fresh one. Keys come from SafeSettings::APPEARANCE_KEYS.
  # On Lite, stored Pro-only values survive (see PlanSettingsGate).
  class AppearanceReset
    def initialize(user, keys = SafeSettings::APPEARANCE_KEYS)
      @user = user
      @keys = keys
    end

    def call
      settings = @user.settings_hash.deep_dup
      @keys.each do |key|
        *parents, leaf = key.split('.')
        container = parents.empty? ? settings : settings.dig(*parents)
        container.delete(leaf) if container.is_a?(Hash)
      end
      settings = PlanSettingsGate.keep_pro_only(settings, @user.settings_hash) if @user.plan_restricted?
      @user.update(settings: settings)
    end
  end
end
