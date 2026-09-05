# frozen_string_literal: true

module Geocoding
  class Search
    # With a max_wait budget, a lookup the rate limiter cannot grant in time
    # returns nil instead of results — distinct from [] so callers can tell a
    # busy limiter from a genuine empty answer (and avoid caching it).
    def self.call(user:, query:, timeout:, fallback_to_default: false, max_wait: nil, **options)
      config = Config.for(user)

      case config.source
      when :env
        RateLimiter.throttle(config, max_wait: max_wait) do
          Geocoder.search(query, **options.merge(timeout: timeout))
        end
      when :user
        user_mode_search(config, query, options, timeout: timeout, max_wait: max_wait)
      else
        # The gem default is public Nominatim, which publishes a hard 1 rps
        # policy, so pace it like any other provider.
        return [] unless fallback_to_default

        RateLimiter.throttle(Config.default_fallback, max_wait: max_wait) do
          Geocoder.search(query, **options.merge(timeout: timeout))
        end
      end
    end

    def self.with_config(config:, query:, timeout:, max_wait: nil, **options)
      return [] unless config.source == :user

      user_mode_search(config, query, options, timeout: timeout, max_wait: max_wait)
    end

    def self.user_mode_search(config, query, options, timeout:, max_wait: nil)
      unless required_fields_present?(config)
        Rails.logger.warn("[Geocoding::Search] Skipping lookup: #{config.provider} config is incomplete")
        return []
      end

      geocoder_query = Geocoder::Query.new(
        query,
        options.merge(lookup: Providers.gem_handle(config.provider), timeout: timeout)
      )
      return [] if geocoder_query.blank?

      # Deliberately after the early returns: a lookup that will not happen
      # must not take a slot other callers are waiting for.
      RateLimiter.throttle(config, max_wait: max_wait) do
        UserLookup.build(config, timeout: timeout).search(geocoder_query)
      end
    end

    def self.required_fields_present?(config)
      return false if Providers.host_required?(config.provider) && config.host.blank?
      return false if Providers.api_key_required?(config.provider) && config.api_key.blank?

      true
    end

    private_class_method :user_mode_search, :required_fields_present?
  end
end
