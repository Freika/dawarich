# frozen_string_literal: true

module Users
  class IssueDestroyToken
    TTL = 1.hour

    def initialize(user)
      @user = user
    end

    def call
      now = Time.now.to_i
      payload = {
        user_id: @user.id,
        purpose: 'account_destroy',
        jti: SecureRandom.uuid,
        iat: now,
        exp: now + TTL.to_i
      }
      JWT.encode(payload, Auth::InternalTokenSecret.call, 'HS256')
    end
  end
end
