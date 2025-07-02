# frozen_string_literal: true

settings = {
  debug_mode: true,
  timeout: 5,
  units: :km,
  cache: Redis.new(url: "#{ENV['REDIS_URL']}/#{ENV.fetch('RAILS_CACHE_DB', 0)}"),
  always_raise: :all,
  http_headers: {
    'User-Agent' => "Dawarich #{APP_VERSION} (https://dawarich.app)"
  },
  cache_options: {
    expiration: 1.day
  }
}

if PHOTON_API_HOST.present?
  settings[:lookup] = :photon
  settings[:use_https] = PHOTON_API_USE_HTTPS
  settings[:photon] = { host: PHOTON_API_HOST }
  settings[:http_headers] = { 'X-Api-Key' => PHOTON_API_KEY } if PHOTON_API_KEY.present?
elsif GEOAPIFY_API_KEY.present?
  settings[:lookup] = :geoapify
  settings[:api_key] = GEOAPIFY_API_KEY
elsif NOMINATIM_API_HOST.present?
  settings[:lookup] = :nominatim
  settings[:nominatim] = { use_https: NOMINATIM_API_USE_HTTPS, host: NOMINATIM_API_HOST }
  settings[:api_key] = NOMINATIM_API_KEY if NOMINATIM_API_KEY.present?
elsif LOCATIONIQ_API_KEY.present?
  settings[:lookup] = :location_iq
  settings[:api_key] = LOCATIONIQ_API_KEY
end

Geocoder.configure(settings)
