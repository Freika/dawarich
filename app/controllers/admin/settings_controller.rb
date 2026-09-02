# frozen_string_literal: true

# Edits Instance settings — values that belong to the deployment rather than to
# a user. A setting the environment pins is shown read-only beside the variable
# holding it and is refused on write, rather than accepted and discarded.
module Admin
  class SettingsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_admin!

    def show
      @settings = resolved_settings
    end

    def update
      refused = apply_submitted_settings

      if refused.any?
        redirect_to admin_settings_path,
                    alert: t('admin.settings.update.pinned', variables: refused.join(', ')),
                    status: :see_other
      else
        redirect_to admin_settings_path, notice: t('admin.settings.update.saved'), status: :see_other
      end
    end

    private

    def ensure_admin!
      user_not_authorized unless current_user&.admin?
    end

    def resolved_settings
      InstanceSettings::Registry.keys.map { |key| InstanceSettings::Resolver.get(key) }
    end

    # Returns the variables that refused a write, so the operator is told which
    # ones to remove from the environment rather than left wondering.
    def apply_submitted_settings
      submitted = params.fetch(:instance_settings, {})
      return [] if submitted.blank?

      submitted.to_unsafe_h.each_with_object([]) do |(key, raw), refused|
        definition = registry_definition(key)
        next if definition.nil?
        # A secret is never rendered back into the form, so the browser posts an
        # empty string for one the operator did not touch. Treating that as a
        # value would erase every stored key on any save — so blank means
        # "unchanged", and clearing one is an explicit checkbox.
        next if definition.secret? && raw.to_s.strip.empty? && !clearing?(definition)

        begin
          InstanceSettings::Resolver.set(definition.key, definition.coerce(raw))
        rescue InstanceSettings::Resolver::PinnedSettingError
          refused << definition.env_var
        end
      end
    end

    def clearing?(definition)
      params.fetch(:instance_settings_clear, {})[definition.key.to_s].present?
    end

    def registry_definition(key)
      InstanceSettings::Registry.fetch(key)
    rescue KeyError
      nil
    end
  end
end
