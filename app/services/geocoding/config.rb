# frozen_string_literal: true

module Geocoding
  class Config
    KOMOOT_HOST = Providers::KOMOOT_HOST
    # The Instance setting whose presence selects each provider, in chain order.
    PROVIDER_KEYS = { photon: :photon_api_host, geoapify: :geoapify_api_key,
                      nominatim: :nominatim_api_host, locationiq: :locationiq_api_key }.freeze

    attr_reader :source, :provider, :host, :api_key, :use_https, :rps

    # Geocoding is an Instance setting: one provider serves everyone on a
    # deployment, so the user no longer changes the answer.
    def self.for(_user = nil)
      resolved_config
    end

    def self.resolved_config
      attributes = resolved_provider_attributes
      return disabled_config if attributes.blank?

      new(**attributes)
    end

    # Walks the same provider chain as the ENV path, but each candidate carries
    # the source that supplied it so the admin page can say whether a value is
    # Pinned by a variable or merely stored. A provider the environment pins
    # outranks every stored one, wherever the stored one sits in the chain.
    def self.resolved_provider_attributes
      candidates = provider_candidates.select { |_provider, primary| primary.value.present? }
      provider, primary = (candidates.select { |_provider, value| value.pinned? }.presence || candidates).first
      return {} if provider.nil?

      { source: primary.source, provider: provider, rps: InstanceSettings::Resolver.value(:reverse_geocoding_rps) }
        .merge(resolved_attributes_for(provider, primary.value))
    end

    def self.provider_candidates
      PROVIDER_KEYS.transform_values { |key| InstanceSettings::Resolver.get(key) }
    end

    def self.resolved_attributes_for(provider, primary_value)
      case provider
      when :photon
        { host: primary_value, api_key: InstanceSettings::Resolver.value(:photon_api_key),
          use_https: resolved_photon_use_https(primary_value) }
      when :nominatim
        { host: primary_value, api_key: InstanceSettings::Resolver.value(:nominatim_api_key),
          use_https: InstanceSettings::Resolver.value(:nominatim_api_use_https) }
      else
        { api_key: primary_value }
      end
    end

    # Hosts that only ever answer over TLS force it on regardless of the flag,
    # matching DawarichSettings.photon_use_https?.
    def self.resolved_photon_use_https(host)
      return true if PHOTON_HTTPS_ONLY_HOSTS.include?(Providers.bare_host(host))

      InstanceSettings::Resolver.value(:photon_api_use_https)
    end

    # Stands in for the geocoder gem's own default lookup, which serves the
    # no-provider-configured fallback. That default is public Nominatim, whose
    # usage policy is one request a second.
    FALLBACK_RPS = 1.0

    def self.default_fallback
      new(source: :fallback, provider: Geocoder.config.lookup, rps: FALLBACK_RPS)
    end

    def self.disabled_config
      new(source: :none)
    end

    private_class_method :disabled_config, :resolved_provider_attributes, :resolved_photon_use_https,
                         :provider_candidates, :resolved_attributes_for

    def initialize(source:, provider: nil, host: nil, api_key: nil, use_https: true, rps: nil)
      @source = source
      @provider = provider
      @host = host
      @api_key = api_key
      @use_https = use_https
      # Normalized here rather than trusted from the caller so a pinned value
      # obeys the same komoot pin and ChibiGeo clamp as a stored one.
      @rps = provider ? RateLimits.for(provider, host).normalize(rps) : nil
      freeze
    end

    def enabled?
      source != :none
    end

    def pinned?
      source == :env
    end

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
