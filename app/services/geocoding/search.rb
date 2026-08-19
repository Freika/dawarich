# frozen_string_literal: true

module Geocoding
  class Search
    HOST_REQUIRED = %i[photon nominatim].freeze
    API_KEY_REQUIRED = %i[geoapify locationiq].freeze

    def self.call(user:, query:, fallback_to_default: false, **options)
      config = Config.for(user)

      case config.source
      when :env
        Geocoder.search(query, **options)
      when :user
        user_mode_search(config, query, options)
      else
        fallback_to_default ? Geocoder.search(query, **options) : []
      end
    end

    def self.with_config(config:, query:, **options)
      return [] unless config.source == :user

      user_mode_search(config, query, options)
    end

    def self.user_mode_search(config, query, options)
      unless required_fields_present?(config)
        Rails.logger.warn("[Geocoding::Search] Skipping lookup: #{config.provider} config is incomplete")
        return []
      end

      geocoder_query = Geocoder::Query.new(
        query,
        options.merge(lookup: UserLookup.gem_handle(config.provider))
      )
      return [] if geocoder_query.blank?

      UserLookup.build(config).search(geocoder_query)
    end

    def self.required_fields_present?(config)
      return false if HOST_REQUIRED.include?(config.provider) && config.host.blank?
      return false if API_KEY_REQUIRED.include?(config.provider) && config.api_key.blank?

      true
    end

    private_class_method :user_mode_search, :required_fields_present?
  end
end
