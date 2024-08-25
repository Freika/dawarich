# frozen_string_literal: true

settings = {
  timeout: 5,
  units: :km,
  cache: Redis.new,
  always_raise: :all,
  cache_options: {
    expiration: 1.day
  }
}

if defined?(PHOTON_API_HOST)
  settings[:lookup] = :photon
  settings[:photon] = { host: PHOTON_API_HOST }
end

Geocoder.configure(settings)
