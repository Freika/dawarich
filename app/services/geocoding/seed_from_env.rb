# frozen_string_literal: true

module Geocoding
  class SeedFromEnv
    PROVIDER_CHAIN = %w[photon geoapify nominatim locationiq].freeze

    def self.call(user)
      new(user).call
    end

    def initialize(user)
      @user = user
    end

    def call
      return unless DawarichSettings.self_hosted?
      return unless DawarichSettings.reverse_geocoding_enabled?

      env_provider_attributes.each { |attrs| create_setting(attrs) }
      activate_chain_winner
    end

    private

    attr_reader :user

    def env_provider_attributes
      attrs = []
      if DawarichSettings.photon_enabled?
        attrs << { provider: 'photon', api_key: PHOTON_API_KEY,
                   config: { 'host' => PHOTON_API_HOST, 'use_https' => DawarichSettings.photon_use_https? } }
      end
      attrs << { provider: 'geoapify', api_key: GEOAPIFY_API_KEY, config: {} } if DawarichSettings.geoapify_enabled?
      if DawarichSettings.nominatim_enabled?
        attrs << { provider: 'nominatim', api_key: NOMINATIM_API_KEY,
                   config: { 'host' => NOMINATIM_API_HOST, 'use_https' => NOMINATIM_API_USE_HTTPS } }
      end
      if DawarichSettings.locationiq_enabled?
        attrs << { provider: 'locationiq', api_key: LOCATIONIQ_API_KEY, config: {} }
      end
      attrs
    end

    def create_setting(attrs)
      return if geocoding_settings.exists?(provider: attrs[:provider])

      setting = user.service_settings.new(service: :geocoding, provider: attrs[:provider], config: attrs[:config])
      setting.api_key = attrs[:api_key]
      setting.save!
    rescue StandardError => e
      Rails.logger.error(
        "Failed to seed #{attrs[:provider]} geocoding setting for user #{user.id}: #{e.class}: #{e.message}"
      )
      ExceptionReporter.call(e, 'Failed to seed geocoding setting from ENV')
      nil
    end

    def activate_chain_winner
      return if geocoding_settings.exists?(active: true)

      winner = PROVIDER_CHAIN.lazy.filter_map { |provider| geocoding_settings.find_by(provider: provider) }.first
      winner&.activate!
    end

    def geocoding_settings
      user.service_settings.service_geocoding
    end
  end
end
