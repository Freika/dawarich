# frozen_string_literal: true

module Admin
  module SettingsHelper
    GEOCODING_SECTIONS = %w[photon geoapify nominatim locationiq rate_limit].freeze
    PROVIDER_SECTIONS = %w[photon geoapify nominatim locationiq].freeze
    SECTION_ICONS = { 'rate_limit' => 'clock', 'points' => 'map-pin', 'map_matching' => 'route' }.freeze

    CHIBIGEO_KEY_URL = 'https://chibigeo.com/docs/guides/dawarich-self-hosted-geocoding?utm_source=dawarich&utm_medium=app&utm_campaign=geocoding_settings'

    def geocoding_provider_name(provider)
      Geocoding::Providers.name(provider)
    end

    def geocoding_in_use?(config, provider)
      config.enabled? && config.provider == provider.to_sym
    end

    def instance_section_title(section)
      return geocoding_provider_name(section) if PROVIDER_SECTIONS.include?(section)

      return t('admin.settings.show.geocoding.rate_limit') if section == 'rate_limit'
      return t('admin.settings.show.map_matching.title') if section == 'map_matching'

      t('admin.settings.show.points.title')
    end

    def instance_section_icon(section)
      SECTION_ICONS.fetch(section, 'globe')
    end

    # What the navigation flags about a section: a secret that needs re-entering
    # outranks the provider being in use, which outranks a pinned value.
    def instance_section_status(section, settings:, unreadable_keys:, geocoding:)
      keys = Admin::SettingsController::SECTIONS.fetch(section)
      return :attention if keys.intersect?(unreadable_keys)
      return :in_use if PROVIDER_SECTIONS.include?(section) && geocoding_in_use?(geocoding, section)

      :pinned if keys.any? { |key| settings.fetch(key).pinned? }
    end

    def instance_section_status_icon(status)
      icon_name, css, label = {
        attention: ['triangle-alert', 'text-warning', t('admin.settings.show.nav_attention')],
        in_use: ['circle-check', 'text-success', t('admin.settings.show.geocoding.in_use')],
        pinned: ['lock', 'text-base-content/70', t('admin.settings.show.nav_pinned')]
      }.fetch(status)

      tag.span(class: 'tooltip tooltip-left', data: { tip: label }) do
        icon(icon_name, class: "size-4 #{css}") + tag.span(label, class: 'sr-only')
      end
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
      when :atlas_url then t('admin.settings.show.fields.atlas_url_hint')
      when :map_matching_enabled then t('admin.settings.show.fields.map_matching_enabled_hint')
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
