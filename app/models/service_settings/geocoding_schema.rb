# frozen_string_literal: true

module ServiceSettings
  class GeocodingSchema
    KOMOOT_HOST = Geocoding::Providers::KOMOOT_HOST
    CHIBIGEO_HOST = Geocoding::Providers::CHIBIGEO_HOST
    CHIBIGEO_BARE_HOST = Geocoding::Providers::CHIBIGEO_BARE_HOST
    HOST_FORMAT = %r{\A[a-z0-9_][a-z0-9._-]*(:\d+)?(/[a-z0-9._/-]*)?\z}

    def initialize(setting)
      @setting = setting
    end

    def normalize
      normalize_host
      force_https_only_hosts
      normalize_rps
    end

    def validate
      validate_provider
      validate_host
      validate_api_key
      validate_chibigeo_key
    end

    def komoot?
      Geocoding::Providers.komoot?(setting.provider, setting.config['host'])
    end

    def chibigeo?
      Geocoding::Providers.chibigeo?(setting.provider, setting.config['host'])
    end

    def paid?
      Geocoding::Providers.api_key_required?(setting.provider)
    end

    private

    attr_reader :setting

    def normalize_host
      host = setting.config['host']
      return if host.blank?

      normalized = host.to_s.strip.downcase.sub(%r{\Ahttps?://}, '').sub(%r{/+\z}, '')
      setting.config['host'] = normalized
    end

    # Runs after normalize_host: the rate ceiling is decided by the host, so it
    # has to be read in its canonical form.
    def normalize_rps
      rate = Geocoding::RateLimits.for(setting.provider, setting.config['host']).normalize(setting.config['rps'])

      if rate.nil?
        setting.config.delete('rps')
      else
        setting.config['rps'] = rate
      end
    end

    def force_https_only_hosts
      setting.config['use_https'] = true if PHOTON_HTTPS_ONLY_HOSTS.include?(bare_host)
    end

    def bare_host
      Geocoding::Providers.bare_host(setting.config['host'])
    end

    def validate_provider
      return if Geocoding::Providers::CHAIN.include?(setting.provider)

      setting.errors.add(:provider, :inclusion)
    end

    def validate_host
      host = setting.config['host']

      if Geocoding::Providers.host_required?(setting.provider) && host.blank?
        setting.errors.add(:base, :host_required, provider: Geocoding::Providers.name(setting.provider))
      elsif host.present? && !host.match?(HOST_FORMAT)
        setting.errors.add(:base, :host_invalid)
      end
    end

    def validate_api_key
      return unless Geocoding::Providers.api_key_required?(setting.provider)
      return if setting.api_key.present?

      setting.errors.add(:base, :api_key_required, provider: Geocoding::Providers.name(setting.provider))
    end

    def validate_chibigeo_key
      return unless chibigeo?
      return if setting.api_key.present?

      setting.errors.add(:base, :chibigeo_api_key_required)
    end
  end
end
