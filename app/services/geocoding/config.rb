# frozen_string_literal: true

module Geocoding
  class Config
    KOMOOT_HOST = Providers::KOMOOT_HOST

    attr_reader :source, :provider, :host, :api_key, :use_https, :rps

    # Geocoding is an Instance setting: one provider serves everyone on a
    # deployment. Behind the flag it resolves that way. With the flag off the
    # historical ENV-or-per-user split is preserved byte for byte, which is the
    # rollback path if the rerouting misbehaves on someone's instance.
    def self.for(user)
      return resolved_config if InstanceSettings.enabled?

      return env_config if DawarichSettings.reverse_geocoding_enabled?

      for_user_settings(user)
    end

    def self.resolved_config
      attributes = resolved_provider_attributes
      return disabled_config if attributes.blank?

      new(**attributes)
    end

    # Walks the same provider chain as the ENV path, but each candidate carries
    # the source that supplied it so the admin page can say whether a value is
    # Pinned by a variable or merely stored.
    def self.resolved_provider_attributes
      rps = InstanceSettings::Resolver.value(:reverse_geocoding_rps)

      photon_host = InstanceSettings::Resolver.get(:photon_api_host)
      if photon_host.value.present?
        return { source: photon_host.source, provider: :photon, host: photon_host.value,
                 api_key: InstanceSettings::Resolver.value(:photon_api_key),
                 use_https: resolved_photon_use_https(photon_host.value), rps: rps }
      end

      geoapify_key = InstanceSettings::Resolver.get(:geoapify_api_key)
      if geoapify_key.value.present?
        return { source: geoapify_key.source, provider: :geoapify, api_key: geoapify_key.value, rps: rps }
      end

      nominatim_host = InstanceSettings::Resolver.get(:nominatim_api_host)
      if nominatim_host.value.present?
        return { source: nominatim_host.source, provider: :nominatim, host: nominatim_host.value,
                 api_key: InstanceSettings::Resolver.value(:nominatim_api_key),
                 use_https: InstanceSettings::Resolver.value(:nominatim_api_use_https), rps: rps }
      end

      locationiq_key = InstanceSettings::Resolver.get(:locationiq_api_key)
      return {} if locationiq_key.value.blank?

      { source: locationiq_key.source, provider: :locationiq, api_key: locationiq_key.value, rps: rps }
    end

    # Hosts that only ever answer over TLS force it on regardless of the flag,
    # matching DawarichSettings.photon_use_https?.
    def self.resolved_photon_use_https(host)
      return true if PHOTON_HTTPS_ONLY_HOSTS.include?(Providers.bare_host(host))

      InstanceSettings::Resolver.value(:photon_api_use_https)
    end

    def self.for_user_settings(user)
      user_id = user.is_a?(User) ? user.id : user
      return disabled_config if user_id.nil?

      setting = ServiceSetting.service_geocoding.find_by(user_id: user_id, active: true)
      return disabled_config if setting.nil?

      unless setting.readable_credentials?
        Rails.logger.warn(
          "Geocoding credentials for user #{user_id} cannot be decrypted; treating geocoding as disabled"
        )
        return disabled_config
      end

      new(
        source: :user,
        provider: setting.provider.to_sym,
        host: setting.host,
        api_key: setting.api_key,
        use_https: setting.use_https,
        rps: setting.rps
      )
    end

    # Stands in for the geocoder gem's own default lookup, which serves the
    # no-provider-configured fallback. That default is public Nominatim, whose
    # usage policy is one request a second.
    FALLBACK_RPS = 1.0

    def self.default_fallback
      new(source: :fallback, provider: Geocoder.config.lookup, rps: FALLBACK_RPS)
    end

    def self.env_config
      new(source: :env, **env_provider_attributes)
    end

    def self.disabled_config
      new(source: :none)
    end

    def self.env_provider_attributes
      if DawarichSettings.photon_enabled?
        { provider: :photon, host: PHOTON_API_HOST, api_key: PHOTON_API_KEY,
          use_https: DawarichSettings.photon_use_https?, rps: REVERSE_GEOCODING_RPS }
      elsif DawarichSettings.geoapify_enabled?
        { provider: :geoapify, api_key: GEOAPIFY_API_KEY, rps: REVERSE_GEOCODING_RPS }
      elsif DawarichSettings.nominatim_enabled?
        { provider: :nominatim, host: NOMINATIM_API_HOST, api_key: NOMINATIM_API_KEY,
          use_https: NOMINATIM_API_USE_HTTPS, rps: REVERSE_GEOCODING_RPS }
      elsif DawarichSettings.locationiq_enabled?
        { provider: :locationiq, api_key: LOCATIONIQ_API_KEY, rps: REVERSE_GEOCODING_RPS }
      else
        {}
      end
    end

    private_class_method :env_config, :disabled_config, :env_provider_attributes,
                         :resolved_provider_attributes, :resolved_photon_use_https

    def initialize(source:, provider: nil, host: nil, api_key: nil, use_https: true, rps: nil)
      @source = source
      @provider = provider
      @host = host
      @api_key = api_key
      @use_https = use_https
      # Normalized here rather than trusted from the caller so an ENV-managed
      # instance obeys the same komoot pin and ChibiGeo clamp as a user row.
      @rps = provider ? RateLimits.for(provider, host).normalize(rps) : nil
      freeze
    end

    def enabled?
      source != :none
    end

    def pinned?
      source == :env
    end

    # Retained so the settings view and the integrations status service keep
    # reading the same question they always asked.
    alias env_managed? pinned?

    def stored?
      source == :stored
    end

    def komoot?
      Providers.komoot?(provider, host)
    end

    def paid_provider?
      provider.present? && Providers.api_key_required?(provider)
    end

    def cache_digest
      Digest::SHA256.hexdigest([source, provider, host, use_https, api_key].join('|'))
    end

    def provider_display_name
      return Providers.name(provider) if provider

      Geocoder.config.lookup.to_s.capitalize
    end
  end
end
