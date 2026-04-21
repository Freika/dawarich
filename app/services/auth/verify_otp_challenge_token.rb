# frozen_string_literal: true

module Auth
  class VerifyOtpChallengeToken
    class InvalidToken < StandardError; end
    class TokenReplayed < InvalidToken; end

    CONSUMED_KEY_PREFIX = 'otp_challenge:consumed:'

    def initialize(token)
      @token = token
    end

    def call
      raise InvalidToken, 'blank token' if @token.blank?

      decoded, = JWT.decode(@token, ENV.fetch('JWT_SECRET_KEY'), true, algorithm: 'HS256')
      raise InvalidToken, 'wrong purpose' unless decoded['purpose'] == 'otp_challenge'
      raise InvalidToken, 'missing jti' if decoded['jti'].blank?

      # Defense in depth: even if exp is far in the future (e.g. someone manufactured
      # a token server-side with a big exp), reject tokens whose iat is older than the
      # configured TTL.
      if decoded['iat'].present? &&
         (Time.now.to_i - decoded['iat'].to_i) > Auth::IssueOtpChallengeToken::TTL.to_i
        raise InvalidToken, 'token too old'
      end

      raise TokenReplayed, 'token already consumed' if token_consumed?(decoded['jti'])

      user = User.find_by(id: decoded['user_id'])
      raise InvalidToken, 'user not found' unless user

      @jti = decoded['jti']
      user
    rescue JWT::DecodeError => e
      raise InvalidToken, e.message
    end

    # Callers invoke this after they have successfully completed the 2FA flow.
    # It marks the token's jti as consumed so replaying the same challenge_token
    # with another OTP guess fails. Key TTL covers the full token TTL.
    def mark_consumed!
      return if @jti.blank?

      Rails.cache.write("#{CONSUMED_KEY_PREFIX}#{@jti}", true,
                        expires_in: Auth::IssueOtpChallengeToken::TTL)
    end

    private

    def token_consumed?(jti)
      Rails.cache.exist?("#{CONSUMED_KEY_PREFIX}#{jti}")
    end
  end
end
