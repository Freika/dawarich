# frozen_string_literal: true

module Auth
  # Verifies an OAuth account-link JWT issued by IssueAccountLinkToken.
  # Performs signature + exp + purpose + jti-replay checks and returns a
  # struct carrying the user plus the OAuth identity to link.
  class VerifyAccountLinkToken
    class InvalidToken < StandardError; end
    class TokenReplayed < InvalidToken; end

    CONSUMED_KEY_PREFIX = 'oauth_account_link:consumed:'

    Result = Struct.new(:user, :provider, :uid, :jti, keyword_init: true)

    def initialize(token)
      @token = token
    end

    def call
      raise InvalidToken, 'blank token' if @token.blank?

      decoded, = JWT.decode(@token, ENV.fetch('JWT_SECRET_KEY'), true, algorithm: 'HS256')
      raise InvalidToken, 'wrong purpose' unless decoded['purpose'] == 'oauth_account_link'

      jti = decoded['jti'].to_s
      raise InvalidToken, 'missing jti' if jti.blank?

      # iat defense-in-depth: reject tokens older than TTL even if exp is wide
      if decoded['iat'].present? &&
         (Time.now.to_i - decoded['iat'].to_i) > Auth::IssueAccountLinkToken::TTL.to_i
        raise InvalidToken, 'token too old'
      end

      raise TokenReplayed, 'token already consumed' if token_consumed?(jti)

      user = User.find_by(id: decoded['user_id'])
      raise InvalidToken, 'user not found' unless user

      provider = decoded['provider'].to_s
      uid = decoded['uid'].to_s
      raise InvalidToken, 'missing provider/uid' if provider.blank? || uid.blank?

      Result.new(user: user, provider: provider, uid: uid, jti: jti)
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    def self.mark_consumed!(jti)
      return if jti.blank?

      Rails.cache.write("#{CONSUMED_KEY_PREFIX}#{jti}", true,
                        expires_in: Auth::IssueAccountLinkToken::TTL)
    end

    private

    def token_consumed?(jti)
      Rails.cache.exist?("#{CONSUMED_KEY_PREFIX}#{jti}")
    end
  end
end
