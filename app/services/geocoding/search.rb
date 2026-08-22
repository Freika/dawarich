# frozen_string_literal: true

module Geocoding
  class Search
    def self.call(user:, query:, fallback_to_default: false, **options)
      config = Config.for(user)

      case config.source
      when :env
        RateLimiter.throttle(config) { Geocoder.search(query, **options) }
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
        options.merge(lookup: Providers.gem_handle(config.provider))
      )
      return [] if geocoder_query.blank?

      # Deliberately after the early returns: a lookup that will not happen
      # must not take a slot other callers are waiting for.
      RateLimiter.throttle(config) { UserLookup.build(config).search(geocoder_query) }
    end

    def self.required_fields_present?(config)
      return false if Providers.host_required?(config.provider) && config.host.blank?
      return false if Providers.api_key_required?(config.provider) && config.api_key.blank?

      true
    end

    private_class_method :user_mode_search, :required_fields_present?
  end
end
