# frozen_string_literal: true

module Auth
  class IssueOtpChallengeToken
    TTL = 5.minutes

    def initialize(user)
      @user = user
    end

    def call
      now = Time.now.to_i
      payload = {
        user_id: @user.id,
        purpose: 'otp_challenge',
        jti: SecureRandom.uuid,
        iat: now,
        exp: now + TTL.to_i
      }
      JWT.encode(payload, Auth::InternalTokenSecret.call, 'HS256')
    end
  end
end
