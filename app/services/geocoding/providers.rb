# frozen_string_literal: true

module Geocoding
  module Providers
    CHAIN = %w[photon geoapify nominatim locationiq].freeze
    HOST_REQUIRED = %w[photon nominatim].freeze
    API_KEY_REQUIRED = %w[geoapify locationiq].freeze
    KOMOOT_HOST = 'photon.komoot.io'
    CHIBIGEO_HOST = 'app.chibigeo.com/v1/photon'
    CHIBIGEO_BARE_HOST = 'app.chibigeo.com'
    NAMES = {
      'photon' => 'Photon', 'geoapify' => 'Geoapify',
      'nominatim' => 'Nominatim', 'locationiq' => 'LocationIQ'
    }.freeze
    GEM_HANDLES = {
      'photon' => :photon, 'geoapify' => :geoapify,
      'nominatim' => :nominatim, 'locationiq' => :location_iq
    }.freeze

    def self.host_required?(provider)
      HOST_REQUIRED.include?(provider.to_s)
    end

    def self.api_key_required?(provider)
      API_KEY_REQUIRED.include?(provider.to_s)
    end

    def self.gem_handle(provider)
      GEM_HANDLES.fetch(provider.to_s)
    end

    def self.name(provider)
      NAMES.fetch(provider.to_s, provider.to_s)
    end

    # Strips the port and any reverse-proxy path suffix so hosts written as
    # "app.chibigeo.com/v1/photon" or "photon.komoot.io:443" still match.
    def self.bare_host(host)
      host.to_s.split('/').first.to_s.split(':').first
    end

    def self.komoot?(provider, host)
      provider.to_s == 'photon' && bare_host(host) == KOMOOT_HOST
    end

    def self.chibigeo?(provider, host)
      provider.to_s == 'photon' && bare_host(host) == CHIBIGEO_BARE_HOST
    end

    # ChibiGeo, Geoapify and LocationIQ count requests against the API key.
    # Komoot and a self-hosted Photon or Nominatim count against the caller's
    # IP, so everyone on one instance shares their allowance.
    def self.metered_per_key?(provider, host)
      api_key_required?(provider) || chibigeo?(provider, host)
    end
  end
end
