# frozen_string_literal: true

Rails.application.config.after_initialize do
  AppleID::JWKS.cache = Rails.cache
rescue NameError, LoadError => e
  Rails.logger.warn "AppleID JWKS cache wiring skipped: #{e.message}"
end
