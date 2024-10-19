# frozen_string_literal: true

settings = {
  timeout: 5,
  units: DISTANCE_UNIT,
  cache: Redis.new,
  always_raise: :all,
  cache_options: {
    expiration: 1.day
  }
}

if defined?(PHOTON_API_HOST)
  settings[:lookup] = :photon
  settings[:photon] = { use_https: PHOTON_API_USE_HTTPS, host: PHOTON_API_HOST }
end

Geocoder.configure(settings)
