# frozen_string_literal: true

config = {
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
}

if ENV['GOOGLE_PLACES_API_KEY'].present?
  config[:lookup] = :google
  config[:api_key] = ENV['GOOGLE_PLACES_API_KEY']
end

Geocoder.configure(config)
