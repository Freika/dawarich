# frozen_string_literal: true

# Wire the apple_id gem's JWKS fetcher through Rails.cache so repeated
# id_token verifications don't hammer Apple's /auth/keys endpoint.
Rails.application.config.after_initialize do
  AppleID::JWKS.cache = Rails.cache
end
