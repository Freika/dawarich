# frozen_string_literal: true

module Auth
  class IssueOtpChallengeToken
    TTL = 5.minutes

    def initialize(user)
      @user = user
    end

    def call
      payload = {
        user_id: @user.id,
        purpose: 'otp_challenge',
        exp: TTL.from_now.to_i
      }
      JWT.encode(payload, ENV.fetch('JWT_SECRET_KEY'), 'HS256')
    end
  end
end
