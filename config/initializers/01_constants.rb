# frozen_string_literal: true

SELF_HOSTED = ENV.fetch('SELF_HOSTED', 'true') == 'true'

MIN_MINUTES_SPENT_IN_CITY = ENV.fetch('MIN_MINUTES_SPENT_IN_CITY', 60).to_i

DISTANCE_UNITS = {
  km: 1000,    # to meters
  mi: 1609.34, # to meters
  m: 1,        # already in meters
  ft: 0.3048,  # to meters
  yd: 0.9144   # to meters
}.freeze

APP_VERSION = File.read('.app_version').strip

# Reverse geocoding settings
PHOTON_API_HOST = ENV.fetch('PHOTON_API_HOST', nil)
PHOTON_API_KEY = ENV.fetch('PHOTON_API_KEY', nil)
PHOTON_API_USE_HTTPS = ENV.fetch('PHOTON_API_USE_HTTPS', 'false') == 'true'

NOMINATIM_API_HOST = ENV.fetch('NOMINATIM_API_HOST', nil)
NOMINATIM_API_KEY = ENV.fetch('NOMINATIM_API_KEY', nil)
NOMINATIM_API_USE_HTTPS = ENV.fetch('NOMINATIM_API_USE_HTTPS', 'true') == 'true'

LOCATIONIQ_API_KEY = ENV.fetch('LOCATIONIQ_API_KEY', nil)

GEOAPIFY_API_KEY = ENV.fetch('GEOAPIFY_API_KEY', nil)
STORE_GEODATA = ENV.fetch('STORE_GEODATA', 'true') == 'true'
# /Reverse geocoding settings

SENTRY_DSN = ENV.fetch('SENTRY_DSN', nil)
MANAGER_URL = SELF_HOSTED ? nil : ENV.fetch('MANAGER_URL', nil)

# Prometheus metrics
METRICS_USERNAME = ENV.fetch('METRICS_USERNAME', 'prometheus')
METRICS_PASSWORD = ENV.fetch('METRICS_PASSWORD', 'prometheus')
# /Prometheus metrics

# Configure OAuth providers based on environment
# Self-hosted: only OpenID Connect, Cloud: only GitHub and Google
OMNIAUTH_PROVIDERS =
  if SELF_HOSTED
    # Self-hosted: only OpenID Connect
    ENV['OIDC_CLIENT_ID'].present? && ENV['OIDC_CLIENT_SECRET'].present? ? %i[openid_connect] : []
  else
    # Cloud: only GitHub and Google
    providers = []

    providers << :github if ENV['GITHUB_OAUTH_CLIENT_ID'].present? && ENV['GITHUB_OAUTH_CLIENT_SECRET'].present?

    providers << :google_oauth2 if ENV['GOOGLE_OAUTH_CLIENT_ID'].present? && ENV['GOOGLE_OAUTH_CLIENT_SECRET'].present?

    providers
  end

# Custom OIDC provider display name
OIDC_PROVIDER_NAME = ENV.fetch('OIDC_PROVIDER_NAME', 'Openid Connect').freeze
