# frozen_string_literal: true

module Geocoding
  class Search
    # With a max_wait budget, a lookup the rate limiter cannot grant in time
    # returns nil instead of results — distinct from [] so callers can tell a
    # busy limiter from a genuine empty answer (and avoid caching it).
    def self.call(user:, query:, fallback_to_default: false, max_wait: nil, **options)
      config = Config.for(user)

      case config.source
      when :env
        # The bare Geocoder.search resolves its provider from the global config
        # the initializer builds at boot. Once the resolver owns provider
        # selection that global is no longer authoritative, so the lookup has to
        # carry its own configuration or it silently falls back to the gem
        # default — public Nominatim — at the rate the operator granted their
        # own server.
        if InstanceSettings.enabled?
          user_mode_search(config, query, options, max_wait: max_wait)
        else
          RateLimiter.throttle(config, max_wait: max_wait) { Geocoder.search(query, **options) }
        end
      when :stored, :user
        user_mode_search(config, query, options, max_wait: max_wait)
      else
        # The gem default is public Nominatim, which publishes a hard 1 rps
        # policy, so pace it like any other provider.
        return [] unless fallback_to_default

        RateLimiter.throttle(Config.default_fallback, max_wait: max_wait) { Geocoder.search(query, **options) }
      end
    end

    # Serves the settings "test connection" button. Accepts any config that
    # names a provider directly: :user for a per-user row, :stored once the
    # resolver owns geocoding. Guarding on :user alone made the button report
    # an empty result forever the moment the source changed.
    DIRECT_SOURCES = %i[user stored env].freeze

    def self.with_config(config:, query:, max_wait: nil, **options)
      return [] unless DIRECT_SOURCES.include?(config.source)
      return [] if config.provider.blank?

      user_mode_search(config, query, options, max_wait: max_wait)
    end

    def self.user_mode_search(config, query, options, max_wait: nil)
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
      RateLimiter.throttle(config, max_wait: max_wait) { UserLookup.build(config).search(geocoder_query) }
    end

    def self.required_fields_present?(config)
      return false if Providers.host_required?(config.provider) && config.host.blank?
      return false if Providers.api_key_required?(config.provider) && config.api_key.blank?

      true
    end

    private_class_method :user_mode_search, :required_fields_present?
  end
end
