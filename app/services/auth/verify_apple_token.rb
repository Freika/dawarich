# frozen_string_literal: true

module Auth
  class VerifyAppleToken
    class InvalidToken < StandardError; end

    def initialize(id_token, nonce: nil)
      @id_token = id_token
      @nonce = nonce
    end

    def call
      raise InvalidToken, 'blank token' if @id_token.blank?
      raise InvalidToken, 'APPLE_BUNDLE_ID not configured' if bundle_id.blank?

      decoded = AppleID::IdToken.decode(@id_token)
      verify_args = { client: bundle_id }
      verify_args[:nonce] = expected_nonce_hash if @nonce.present?

      decoded.verify!(**verify_args)

      log_missing_nonce_breadcrumb if @nonce.blank?

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

    def expected_nonce_hash
      Digest::SHA256.hexdigest(@nonce.to_s)
    end

    def log_missing_nonce_breadcrumb
      return unless defined?(Sentry)

      Sentry.capture_message(
        'apple_id_token_missing_nonce',
        level: :warning,
        extra: { hint: 'Hard-require nonce after mobile client rollout' }
      )
    rescue StandardError
      nil
    end
  end
end
