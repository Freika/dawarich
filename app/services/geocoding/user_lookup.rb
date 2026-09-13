# frozen_string_literal: true

module Geocoding
  class UserLookup
    def self.build(config)
      lookup = Geocoder::Lookup.get(Providers.gem_handle(config.provider)).class.new
      merged = merged_configuration(config)
      lookup.define_singleton_method(:configuration) { merged }
      lookup.singleton_class.send(:private, :configuration)
      lookup
    end

    def self.merged_configuration(config)
      base = Geocoder.config_for_lookup(Providers.gem_handle(config.provider))
      base.merge(configuration_overrides(config, base))
    end

    def self.configuration_overrides(config, base)
      case config.provider
      when :photon
        overrides = { host: config.host, use_https: config.use_https }
        if config.api_key.present?
          overrides[:http_headers] = base[:http_headers].to_h.merge('X-Api-Key' => config.api_key)
        end
        overrides
      when :nominatim
        { host: config.host, use_https: config.use_https, api_key: config.api_key }
      else
        { api_key: config.api_key }
      end
    end

    private_class_method :merged_configuration, :configuration_overrides
  end
end
