# frozen_string_literal: true

module ServiceSettings
  class GeocodingSchema
    PROVIDERS = %w[photon geoapify nominatim locationiq].freeze
    PROVIDER_NAMES = {
      'photon' => 'Photon', 'geoapify' => 'Geoapify',
      'nominatim' => 'Nominatim', 'locationiq' => 'LocationIQ'
    }.freeze
    HOST_REQUIRED = %w[photon nominatim].freeze
    API_KEY_REQUIRED = %w[geoapify locationiq].freeze
    KOMOOT_HOST = 'photon.komoot.io'
    CHIBIGEO_HOST = 'app.chibigeo.com/v1/photon'
    CHIBIGEO_BARE_HOST = 'app.chibigeo.com'
    HOST_FORMAT = %r{\A[a-z0-9_][a-z0-9._-]*(:\d+)?(/[a-z0-9._/-]*)?\z}

    def initialize(setting)
      @setting = setting
    end

    def normalize
      normalize_host
      force_https_only_hosts
    end

    def validate
      validate_provider
      validate_host
      validate_api_key
      validate_chibigeo_key
    end

    def komoot?
      setting.provider == 'photon' && bare_host == KOMOOT_HOST
    end

    def chibigeo?
      setting.provider == 'photon' && bare_host == CHIBIGEO_BARE_HOST
    end

    def paid?
      API_KEY_REQUIRED.include?(setting.provider)
    end

    private

    attr_reader :setting

    def normalize_host
      host = setting.config['host']
      return if host.blank?

      normalized = host.to_s.strip.downcase.sub(%r{\Ahttps?://}, '').sub(%r{/+\z}, '')
      setting.config['host'] = normalized
    end

    def force_https_only_hosts
      setting.config['use_https'] = true if PHOTON_HTTPS_ONLY_HOSTS.include?(bare_host)
    end

    def bare_host
      setting.config['host'].to_s.split('/').first.to_s.split(':').first
    end

    def validate_provider
      return if PROVIDERS.include?(setting.provider)

      setting.errors.add(:provider, :inclusion)
    end

    def validate_host
      host = setting.config['host']

      if HOST_REQUIRED.include?(setting.provider) && host.blank?
        setting.errors.add(:base, :host_required, provider: provider_name)
      elsif host.present? && !host.match?(HOST_FORMAT)
        setting.errors.add(:base, :host_invalid)
      end
    end

    def validate_api_key
      return unless API_KEY_REQUIRED.include?(setting.provider)
      return if setting.api_key.present?

      setting.errors.add(:base, :api_key_required, provider: provider_name)
    end

    def validate_chibigeo_key
      return unless chibigeo?
      return if setting.api_key.present?

      setting.errors.add(:base, :chibigeo_api_key_required)
    end

    def provider_name
      PROVIDER_NAMES.fetch(setting.provider, setting.provider.to_s)
    end
  end
end
