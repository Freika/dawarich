# frozen_string_literal: true

module InstanceSettings
  class GeocodingInput
    include UrlValidatable

    HOST_KEYS = %i[photon_api_host nominatim_api_host].freeze

    attr_reader :values, :errors

    def initialize(values)
      @values = values.dup
      @errors = []

      normalize_hosts
      validate_hosts
      validate_host_addresses if valid?
      drop_komoot_key
      validate_chibigeo_key
    end

    def valid?
      errors.empty?
    end

    private

    def normalize_hosts
      HOST_KEYS.each do |key|
        next unless values[key].is_a?(String)

        values[key] = values[key].strip.downcase.sub(%r{\Ahttps?://}, '').sub(%r{/+\z}, '')
      end
    end

    def validate_hosts
      invalid = HOST_KEYS.any? do |key|
        values[key].present? && !values[key].match?(ServiceSettings::GeocodingSchema::HOST_FORMAT)
      end
      errors << I18n.t('admin.settings.update.host_invalid') if invalid
    end

    def validate_host_addresses
      HOST_KEYS.each do |key|
        host = values[key]
        next if host.blank? || known_public_host?(key, host)

        validate_integration_url!("https://#{host}")
      rescue UrlValidatable::BlockedUrlError => e
        next if unresolvable_host?(host)

        errors << I18n.t('admin.settings.update.host_blocked', reason: blocked_reason(e, host))
      end
    end

    def known_public_host?(key, host)
      key == :photon_api_host &&
        (Geocoding::Providers.komoot?('photon', host) || Geocoding::Providers.chibigeo?('photon', host))
    end

    def blocked_reason(error, host)
      unresolvable = I18n.t('services.concerns.url_validatable.unresolvable_host', host: uri_host(host))
      return I18n.t('services.concerns.url_validatable.blocked_address') if error.message == unresolvable

      error.message
    end

    def unresolvable_host?(host)
      Socket.getaddrinfo(uri_host(host), nil)
      false
    rescue SocketError, URI::InvalidURIError
      true
    end

    def uri_host(host)
      URI.parse("https://#{host}").host.to_s
    end

    def drop_komoot_key
      return unless values.key?(:photon_api_host)
      return unless Geocoding::Providers.komoot?('photon', photon_host)
      return if Resolver.pinned?(:photon_api_key)

      values[:photon_api_key] = nil
    end

    def validate_chibigeo_key
      return unless values.key?(:photon_api_host) || values.key?(:photon_api_key)
      return unless Geocoding::Providers.chibigeo?('photon', photon_host)

      key = values.key?(:photon_api_key) ? values[:photon_api_key] : Resolver.value(:photon_api_key)
      errors << I18n.t('admin.settings.update.chibigeo_key_required') if key.blank?
    end

    def photon_host
      values.key?(:photon_api_host) ? values[:photon_api_host] : Resolver.value(:photon_api_host)
    end
  end
end
