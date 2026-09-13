# frozen_string_literal: true

module Admin
  module SettingsHelper
    # Each geocoding provider with the settings it reads, in the order the
    # resolver tries them — the page lists them in that order on purpose.
    GEOCODING_PROVIDERS = {
      photon: %i[photon_api_host photon_api_key photon_api_use_https],
      geoapify: %i[geoapify_api_key],
      nominatim: %i[nominatim_api_host nominatim_api_key nominatim_api_use_https],
      locationiq: %i[locationiq_api_key]
    }.freeze

    CHIBIGEO_KEY_URL = 'https://chibigeo.com/docs/guides/dawarich?utm_source=dawarich&utm_medium=app&utm_campaign=geocoding_settings'

    def geocoding_provider_name(provider)
      Geocoding::Providers.name(provider)
    end

    def geocoding_in_use?(config, provider)
      config.enabled? && config.provider == provider
    end

    # The variable that pins the setting choosing this provider, when one does.
    def geocoding_pinning_variable(config)
      return unless config.pinned?

      InstanceSettings::Registry.fetch(Geocoding::Config::PROVIDER_KEYS.fetch(config.provider)).env_var
    end

    def instance_setting_hint(setting, settings)
      case setting.key
      when :photon_api_host, :nominatim_api_host then t('admin.settings.show.fields.host_hint')
      when :photon_api_use_https
        t('admin.settings.show.geocoding.https_locked') if https_locked?(setting, settings)
      when :reverse_geocoding_rps then t('admin.settings.show.fields.rps_hint')
      when :store_geodata then t('admin.settings.show.fields.store_geodata_hint')
      else
        t('admin.settings.show.fields.api_key_keep_hint') if secret_kept?(setting)
      end
    end

    def komoot_host?(geocoding)
      geocoding_in_use?(geocoding, :photon) && geocoding.komoot?
    end

    # Some Photon hosts only answer over TLS, and the resolver forces HTTPS for
    # them whatever is stored, so the toggle must not claim otherwise.
    def https_locked?(setting, settings)
      setting.key == :photon_api_use_https &&
        PHOTON_HTTPS_ONLY_HOSTS.include?(Geocoding::Providers.bare_host(settings.fetch(:photon_api_host).value))
    end

    # A whole-number rate reads as "5", not "5.0", which browsers localise to "5,0".
    def instance_setting_display_value(setting)
      value = setting.value
      value.is_a?(Float) && (value % 1).zero? ? value.to_i : value
    end

    def instance_setting_placeholder(setting)
      return '' unless InstanceSettings::Registry.fetch(setting.key).secret? && setting.value.present?

      setting.pinned? ? '••••••••' : t('admin.settings.show.secret_set')
    end

    private

    def secret_kept?(setting)
      InstanceSettings::Registry.fetch(setting.key).secret? && setting.value.present? && !setting.pinned?
    end
  end
end
