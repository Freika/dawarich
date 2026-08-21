# frozen_string_literal: true

module Geocoding
  class Config
    KOMOOT_HOST = 'photon.komoot.io'

    attr_reader :source, :provider, :host, :api_key, :use_https

    def self.for(user)
      return env_config if DawarichSettings.reverse_geocoding_enabled?

      for_user_settings(user)
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
        use_https: setting.use_https
      )
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
          use_https: DawarichSettings.photon_use_https? }
      elsif DawarichSettings.geoapify_enabled?
        { provider: :geoapify, api_key: GEOAPIFY_API_KEY }
      elsif DawarichSettings.nominatim_enabled?
        { provider: :nominatim, host: NOMINATIM_API_HOST, api_key: NOMINATIM_API_KEY,
          use_https: NOMINATIM_API_USE_HTTPS }
      elsif DawarichSettings.locationiq_enabled?
        { provider: :locationiq, api_key: LOCATIONIQ_API_KEY }
      else
        {}
      end
    end

    private_class_method :env_config, :disabled_config, :env_provider_attributes

    def initialize(source:, provider: nil, host: nil, api_key: nil, use_https: true)
      @source = source
      @provider = provider
      @host = host
      @api_key = api_key
      @use_https = use_https
      freeze
    end

    def enabled?
      source != :none
    end

    def env_managed?
      source == :env
    end

    def komoot?
      provider == :photon && host.to_s.split(':').first == KOMOOT_HOST
    end

    def paid_provider?
      provider.present? && Providers.api_key_required?(provider)
    end

    def cache_digest
      Digest::SHA256.hexdigest([source, provider, host, use_https].join('|'))
    end

    def provider_display_name
      return Providers.name(provider) if provider

      Geocoder.config.lookup.to_s.capitalize
    end
  end
end
