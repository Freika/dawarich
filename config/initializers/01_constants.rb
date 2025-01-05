# frozen_string_literal: true

MIN_MINUTES_SPENT_IN_CITY = ENV.fetch('MIN_MINUTES_SPENT_IN_CITY', 60).to_i
REVERSE_GEOCODING_ENABLED = ENV.fetch('REVERSE_GEOCODING_ENABLED', 'true') == 'true'
PHOTON_API_HOST = ENV.fetch('PHOTON_API_HOST', nil)
PHOTON_API_KEY = ENV.fetch('PHOTON_API_KEY', nil)
PHOTON_API_USE_HTTPS = ENV.fetch('PHOTON_API_USE_HTTPS', 'true') == 'true'
DISTANCE_UNIT = ENV.fetch('DISTANCE_UNIT', 'km').to_sym
APP_VERSION = File.read('.app_version').strip
TELEMETRY_STRING = Base64.encode64('IjVFvb8j3P9-ArqhSGav9j8YcJaQiuNIzkfOPKQDk2lvKXqb8t1NSRv50oBkaKtlrB_ZRzO9NdurpMtncV_HYQ==')
TELEMETRY_URL = 'https://influxdb2.frey.today/api/v2/write'
