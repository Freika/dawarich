# frozen_string_literal: true

module Auth
  # Resolves the signing secret for the short-lived JWT handed to the iOS /
  # Android apps after a successful web sign-in (see
  # ApplicationController#after_sign_in_path_for). The token only carries the
  # user's api_key back to the device over the redirect URL.
  #
  # The mobile clients base64-decode the JWT payload and read api_key WITHOUT
  # verifying the signature, and nothing verifies the token server-side either.
  # So any non-empty String works — the secret exists purely so JWT.encode does
  # not raise on a nil HMAC key.
  #
  # Cloud requires an explicit AUTH_JWT_SECRET_KEY (enforced at boot by
  # config/initializers/auth_jwt_secret_key.rb). Self-hosted instances fall
  # back to Rails.application.secret_key_base, which every Rails app already
  # has, so self-hosters need no extra configuration for mobile sign-in to work.
  module MobileHandoffSecret
    module_function

    def call
      ENV['AUTH_JWT_SECRET_KEY'].presence || Rails.application.secret_key_base
    end
  end
end
