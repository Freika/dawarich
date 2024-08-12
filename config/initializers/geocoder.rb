# frozen_string_literal: true

config = {
  # geocoding service request timeout, in seconds (default 3):
  timeout: 10,

  # set default units to kilometers:
  units: :km,

  # caching (see Caching section below for details):
  cache: Redis.new,
  cache_options: {
    expiration: 1.day # Defaults to `nil`
    # prefix: "another_key:" # Defaults to `geocoder:`
  },
  always_raise: :all
}

if GOOGLE_PLACES_API_KEY.present?
  config[:lookup] = :google
  config[:api_key] = GOOGLE_PLACES_API_KEY
end

Geocoder.configure(config)
