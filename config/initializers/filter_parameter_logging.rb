# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += %i[
  passw secret token _key crypt salt certificate otp ssn cvv cvc latitude longitude lat lng
]

SENSITIVE_SETTINGS_KEYS = %w[immich_api_key photoprism_api_key].freeze

Rails.application.config.filter_parameters += [
  lambda do |key, value|
    next unless key.to_s == 'settings' && value.is_a?(String)

    parsed = JSON.parse(value)
    SENSITIVE_SETTINGS_KEYS.each do |sensitive_key|
      parsed[sensitive_key] = '[FILTERED]' if parsed[sensitive_key].present?
    end
    value.replace(parsed.to_json)
  rescue JSON::ParseError, TypeError
    # Not valid JSON — leave the value untouched
  end
]
