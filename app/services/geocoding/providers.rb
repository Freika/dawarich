# frozen_string_literal: true

module Geocoding
  module Providers
    CHAIN = %w[photon geoapify nominatim locationiq].freeze
    HOST_REQUIRED = %w[photon nominatim].freeze
    API_KEY_REQUIRED = %w[geoapify locationiq].freeze
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
  end
end
