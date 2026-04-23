# frozen_string_literal: true

require 'bcrypt'

class Api::V1::Auth::SessionsController < Api::V1::Auth::BaseController
  # A pre-computed bcrypt hash used to run a dummy password comparison when
  # no user is found for the submitted email. This equalises response time
  # across existent-vs-nonexistent accounts, closing a user-enumeration
  # side channel.
  DUMMY_PASSWORD_HASH = BCrypt::Password.create(SecureRandom.hex(16)).to_s.freeze

  def create
    user = User.find_by(email: params[:email]&.downcase)

    authenticated = constant_time_authenticate(user, params[:password].to_s)

    return render_auth_error('Invalid email or password') unless authenticated

    if DawarichSettings.two_factor_available? && user.otp_required_for_login?
      challenge_token = Auth::IssueOtpChallengeToken.new(user).call
      render json: {
        two_factor_required: true,
        challenge_token: challenge_token,
        ttl: Auth::IssueOtpChallengeToken::TTL.to_i
      }, status: :accepted
      return
    end

    render_auth_success(user)
  end

  private

  # Always performs a bcrypt verification whether or not the user exists, so
  # response time does not leak account existence.
  def constant_time_authenticate(user, password)
    if user
      user.valid_password?(password)
    else
      # Run bcrypt against a dummy hash; result is always false.
      BCrypt::Password.new(DUMMY_PASSWORD_HASH).is_password?(password)
      false
    end
  end
end
