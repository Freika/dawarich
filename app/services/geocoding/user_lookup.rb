# frozen_string_literal: true

module Geocoding
  class UserLookup
    # Raised when a Photon server answers forward search (/api) with 404,
    # which is how one running in reverse-only mode reports it.
    class ForwardSearchUnavailable < Geocoder::Error; end

    module PhotonForwardSearch
      private

      def make_api_request(query)
        response = super
        if response.code.to_i == 404 && !query.reverse_geocode?
          raise ForwardSearchUnavailable, 'Photon server does not support forward search'
        end

        response
      end
    end

    def self.build(config)
      lookup = Geocoder::Lookup.get(Providers.gem_handle(config.provider)).class.new
      merged = merged_configuration(config)
      lookup.define_singleton_method(:configuration) { merged }
      lookup.singleton_class.send(:private, :configuration)
      lookup.extend(PersistentHttp::Lookup)
      lookup.extend(PhotonForwardSearch) if config.provider == :photon
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
        overrides[:language] = config.language if config.language.present?
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
