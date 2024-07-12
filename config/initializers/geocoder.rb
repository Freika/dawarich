# frozen_string_literal: true

Geocoder.configure(
  # geocoding service request timeout, in seconds (default 3):
  # timeout: 5,

  # set default units to kilometers:
  units: :km,

  # caching (see Caching section below for details):
  cache: Redis.new,
  cache_options: {
    expiration: 1.day # Defaults to `nil`
    # prefix: "another_key:" # Defaults to `geocoder:`
  }
)
