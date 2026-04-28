# frozen_string_literal: true

module Auth
  # Verifies an Apple ID token sent by a mobile client (id_token from
  # ASAuthorizationController / Sign in with Apple).
  #
  # Delegates JWKS fetching, signature verification, and iss/aud/exp/iat
  # checks to the `apple_id` gem so we don't have to maintain this against
  # Apple's evolving spec. JWKS caching is wired through `Rails.cache` in
  # config/initializers/apple_id.rb.
  class VerifyAppleToken
    class InvalidToken < StandardError; end

    def initialize(id_token)
      @id_token = id_token
    end

    def call
      raise InvalidToken, 'blank token' if @id_token.blank?
      raise InvalidToken, 'APPLE_BUNDLE_ID not configured' if bundle_id.blank?

      decoded = AppleID::IdToken.decode(@id_token)
      decoded.verify!(client: bundle_id)

      {
        sub: decoded.sub,
        email: decoded.email,
        email_verified: decoded.email_verified?,
        is_private_email: decoded.is_private_email?
      }
    rescue AppleID::IdToken::VerificationFailed, JSON::JWT::Exception => e
      raise InvalidToken, e.message
    end

    private

    def bundle_id
      ENV['APPLE_BUNDLE_ID']
    end
  end
end
