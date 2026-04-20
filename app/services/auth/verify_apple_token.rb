# frozen_string_literal: true

module Auth
  class VerifyAppleToken
    class InvalidToken < StandardError; end

    APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys'
    APPLE_ISSUER   = 'https://appleid.apple.com'
    JWKS_CACHE_TTL = 1.hour

    def initialize(id_token)
      @id_token = id_token
    end

    def call
      raise InvalidToken, 'blank token' if @id_token.blank?
      raise InvalidToken, 'APPLE_BUNDLE_ID not configured' if expected_audience.blank?

      decoded, _header = JWT.decode(
        @id_token,
        nil,
        true,
        {
          algorithms: ['RS256'],
          jwks: fetch_jwks_proc,
          iss: APPLE_ISSUER,
          verify_iss: true,
          aud: expected_audience,
          verify_aud: true
        }
      )
      decoded.symbolize_keys
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    private

    def expected_audience
      ENV['APPLE_BUNDLE_ID']
    end

    def fetch_jwks_proc
      ->(options) { { keys: fetch_jwks(force: options[:invalidate]) } }
    end

    def fetch_jwks(force: false)
      Rails.cache.fetch('apple_jwks', expires_in: JWKS_CACHE_TTL, force: force) do
        body = Net::HTTP.get(URI(APPLE_JWKS_URL))
        parsed = JSON.parse(body, symbolize_names: true)
        parsed[:keys]
      end
    end
  end
end
