# frozen_string_literal: true

module Auth
  # Resolves the signing/verification secret for tokens that are issued
  # AND verified by Dawarich itself (OTP challenge, OAuth account-link,
  # account-destroy confirmation). These tokens never cross a service
  # boundary, so any locally-available secret works.
  #
  # Cloud uses the explicit `JWT_SECRET_KEY` so this matches the secret
  # already shared with the Manager service. Self-hosted instances fall
  # back to `Rails.application.secret_key_base`, which every Rails app
  # already has — so self-hosters don't need a separate JWT_SECRET_KEY
  # for these flows to work.
  #
  # Do NOT use this for cross-service tokens (subscription webhooks,
  # `User#generate_subscription_token`) — those must keep using
  # `ENV.fetch('JWT_SECRET_KEY')` directly because the Manager validates
  # them with the shared key.
  module InternalTokenSecret
    module_function

    def call
      ENV['JWT_SECRET_KEY'].presence || Rails.application.secret_key_base
    end
  end
end
