# frozen_string_literal: true

settings = {
  timeout: 5,
  units: DISTANCE_UNIT,
  cache: Redis.new,
  always_raise: :all,
  use_https: PHOTON_API_USE_HTTPS,
  http_headers: { 'User-Agent' => "Dawarich #{APP_VERSION} (https://dawarich.app)" },
  cache_options: {
    expiration: 1.day
  }
}

if PHOTON_API_HOST.present?
  settings[:lookup] = :photon
  settings[:photon] = { use_https: PHOTON_API_USE_HTTPS, host: PHOTON_API_HOST }
  settings[:http_headers] = { 'X-Api-Key' => PHOTON_API_KEY } if defined?(PHOTON_API_KEY)
elsif GEOAPIFY_API_KEY.present?
  settings[:lookup] = :geoapify
  settings[:api_key] = GEOAPIFY_API_KEY
end

Geocoder.configure(settings)
