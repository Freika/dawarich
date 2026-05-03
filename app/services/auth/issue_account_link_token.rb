# frozen_string_literal: true

module Auth
  # Issues a short-lived signed JWT that, when presented back to
  # `/auth/account_link`, links an OAuth identity (Apple/Google) to an
  # existing Dawarich account. The token is emailed to the account's
  # registered email address — clicking the link is the user's proof that
  # they control the email and consent to the link.
  class IssueAccountLinkToken
    TTL = 15.minutes

    def initialize(user, provider:, uid:)
      @user = user
      @provider = provider
      @uid = uid
    end

    def call
      now = Time.now.to_i
      payload = {
        user_id: @user.id,
        provider: @provider,
        uid: @uid,
        purpose: 'oauth_account_link',
        jti: SecureRandom.uuid,
        iat: now,
        exp: now + TTL.to_i
      }
      JWT.encode(payload, Auth::InternalTokenSecret.call, 'HS256')
    end
  end
end
