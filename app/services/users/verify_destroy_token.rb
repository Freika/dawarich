# frozen_string_literal: true

module Users
  class VerifyDestroyToken
    class InvalidToken < StandardError; end
    class TokenReplayed < InvalidToken; end

    CONSUMED_KEY_PREFIX = 'account_destroy:consumed:'

    Result = Struct.new(:user, :jti, keyword_init: true)

    def initialize(token)
      @token = token
    end

    def call
      raise InvalidToken, 'blank token' if @token.blank?

      decoded, = JWT.decode(@token, Auth::InternalTokenSecret.call, true, algorithm: 'HS256')
      raise InvalidToken, 'wrong purpose' unless decoded['purpose'] == 'account_destroy'

      jti = decoded['jti'].to_s
      raise InvalidToken, 'missing jti' if jti.blank?

      if decoded['iat'].present? &&
         (Time.now.to_i - decoded['iat'].to_i) > Users::IssueDestroyToken::TTL.to_i
        raise InvalidToken, 'token too old'
      end

      raise TokenReplayed, 'token already consumed' if token_consumed?(jti)

      user = User.unscoped.find_by(id: decoded['user_id'])
      raise InvalidToken, 'user not found' unless user
      raise InvalidToken, 'user already deleted' if user.deleted?

      Result.new(user: user, jti: jti)
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    def self.consume!(jti)
      return false if jti.blank?

      Rails.cache.write(
        "#{CONSUMED_KEY_PREFIX}#{jti}",
        true,
        expires_in: Users::IssueDestroyToken::TTL,
        unless_exist: true
      )
    end

    private

    def token_consumed?(jti)
      Rails.cache.exist?("#{CONSUMED_KEY_PREFIX}#{jti}")
    end
  end
end
