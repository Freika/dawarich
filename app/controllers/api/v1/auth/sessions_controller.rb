# frozen_string_literal: true

class Api::V1::Auth::SessionsController < Api::V1::Auth::BaseController
  def create
    user = User.find_by(email: params[:email]&.downcase)

    return render_auth_error('Invalid email or password') unless user&.valid_password?(params[:password])

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
end
