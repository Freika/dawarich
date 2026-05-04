# frozen_string_literal: true

module Auth
  class VerifyGoogleToken
    class InvalidToken < StandardError; end

    def initialize(id_token, nonce: nil)
      @id_token = id_token
      @nonce = nonce
    end

    def call
      raise InvalidToken, 'blank token' if @id_token.blank?

      client_ids = [
        ENV['GOOGLE_IOS_CLIENT_ID'],
        ENV['GOOGLE_ANDROID_CLIENT_ID'],
        ENV['GOOGLE_OAUTH_CLIENT_ID']
      ].compact
      raise InvalidToken, 'Google client IDs not configured' if client_ids.empty?

      claims = GoogleIDToken::Validator.new.check(@id_token, client_ids)
      raise InvalidToken, 'validator returned nil' if claims.nil?

      claims = claims.symbolize_keys
      verify_nonce!(claims)

      claims
    rescue GoogleIDToken::ValidationError => e
      raise InvalidToken, e.message
    end

    private

    def verify_nonce!(claims)
      if @nonce.blank?
        log_missing_nonce_breadcrumb
        return
      end

      claim_nonce = claims[:nonce].to_s
      return if ActiveSupport::SecurityUtils.secure_compare(claim_nonce, @nonce.to_s)

      raise InvalidToken, 'nonce mismatch'
    end

    def log_missing_nonce_breadcrumb
      return unless defined?(Sentry)

      Sentry.capture_message(
        'google_id_token_missing_nonce',
        level: :warning,
        extra: { hint: 'Hard-require nonce after mobile client rollout' }
      )
    rescue StandardError
      nil
    end
  end
end
