# frozen_string_literal: true

class Api::V1::Auth::OtpChallengesController < Api::V1::Auth::BaseController
  def create
    verifier = Auth::VerifyOtpChallengeToken.new(params[:challenge_token])
    user = verifier.call
  rescue Auth::VerifyOtpChallengeToken::InvalidToken => e
    render_auth_error("Invalid or expired challenge: #{e.message}")
  else
    otp_code = params[:otp_code].to_s.strip
    if user.validate_and_consume_otp!(otp_code) || user.invalidate_otp_backup_code!(otp_code)
      verifier.mark_consumed!
      render_auth_success(user)
    else
      render_auth_error('Invalid two-factor code')
    end
  end
end
