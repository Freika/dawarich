# frozen_string_literal: true

class SentryLogRedactor
  SENSITIVE_KEYS = %w[
    password password_confirmation token api_key secret authorization
    access_token refresh_token otp ssn credit_card card_number cvv
  ].freeze

  EMAIL_PATTERN = /[\w._%+-]+@[\w.-]+\.[A-Za-z]{2,}/

  FILTERED = '[FILTERED]'
  EMAIL = '[EMAIL]'

  def self.call(log)
    if log.attributes.is_a?(Hash)
      log.attributes.each do |key, value|
        normalized = key.to_s.downcase.tr('-', '_')
        if SENSITIVE_KEYS.any? { |k| normalized.include?(k) }
          log.attributes[key] = FILTERED
        elsif value.is_a?(String) && value.match?(EMAIL_PATTERN)
          log.attributes[key] = value.gsub(EMAIL_PATTERN, EMAIL)
        end
      end
    end

    log.body = log.body.gsub(EMAIL_PATTERN, EMAIL) if log.body.is_a?(String)

    log
  end
end
