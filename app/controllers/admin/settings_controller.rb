# frozen_string_literal: true

# Edits Instance settings — values that belong to the deployment rather than to
# a user. A setting the environment pins is shown read-only beside the variable
# holding it and is refused on write, rather than accepted and discarded.
module Admin
  class SettingsController < ApplicationController
    include FlashStreamable

    SECTIONS = {
      'photon' => %i[photon_api_host photon_api_key photon_api_use_https],
      'geoapify' => %i[geoapify_api_key],
      'nominatim' => %i[nominatim_api_host nominatim_api_key nominatim_api_use_https],
      'locationiq' => %i[locationiq_api_key],
      'rate_limit' => %i[reverse_geocoding_rps],
      'points' => %i[store_geodata]
    }.freeze

    before_action :authenticate_user!
    before_action :authenticate_self_hosted!
    before_action :ensure_admin!

    def show
      @settings = InstanceSettings::Registry.keys.index_with { |key| InstanceSettings::Resolver.get(key) }
      @unreadable_keys = unreadable_secret_keys
      @geocoding = Geocoding::Config.resolved_config
      @legacy_user_geocoding = ServiceSetting.service_geocoding.where(active: true).exists?
      @section = params[:section].presence_in(SECTIONS.keys) || default_section
    end

    def update
      back = admin_settings_path(section: params[:section].presence_in(SECTIONS.keys))
      input = InstanceSettings::GeocodingInput.new(submitted_values)
      return redirect_to back, alert: input.errors.join(' '), status: :see_other unless input.valid?

      refused = apply_settings(input.values)

      if refused.any?
        redirect_to back, alert: t('admin.settings.update.pinned', variables: refused.join(', ')), status: :see_other
      else
        redirect_to back, notice: t('admin.settings.update.saved'), status: :see_other
      end
    end

    def test_geocoding
      type, message = Geocoding::ProviderTest.call

      respond_to do |format|
        format.turbo_stream { render turbo_stream: stream_flash(type == :notice ? :notice : :error, message) }
        format.html { redirect_to admin_settings_path, type => message, status: :see_other }
      end
    end

    private

    def default_section
      @geocoding.enabled? ? @geocoding.provider.to_s : SECTIONS.keys.first
    end

    def ensure_admin!
      user_not_authorized unless current_user&.admin?
    end

    # The resolver treats an undecryptable secret as unset, which on its own
    # renders identically to one that was never stored.
    def unreadable_secret_keys
      InstanceSetting.where(key: InstanceSettings::Registry.secret_keys.map(&:to_s))
                     .reject(&:readable_value?)
                     .map { |setting| setting.key.to_sym }
    end

    def submitted_values
      submitted = params.fetch(:instance_settings, {})
      return {} if submitted.blank?

      submitted.to_unsafe_h.each_with_object({}) do |(key, raw), values|
        definition = registry_definition(key)
        next if definition.nil?
        # A secret is never rendered back into the form, so the browser posts an
        # empty string for one the operator did not touch. Treating that as a
        # value would erase every stored key on any save — so blank means
        # "unchanged", and clearing one is an explicit checkbox.
        next if definition.secret? && raw.to_s.strip.empty? && !clearing?(definition)

        values[definition.key] = definition.coerce(raw)
      end
    end

    # Returns the variables that refused a write, so the operator is told which
    # ones to remove from the environment rather than left wondering.
    def apply_settings(values)
      values.each_with_object([]) do |(key, value), refused|
        InstanceSettings::Resolver.set(key, value)
      rescue InstanceSettings::Resolver::PinnedSettingError
        refused << InstanceSettings::Registry.fetch(key).env_var
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
