# frozen_string_literal: true

class Api::V1::Auth::OtpChallengesController < Api::V1::Auth::BaseController
  def create
    verifier = Auth::VerifyOtpChallengeToken.new(params[:challenge_token])
    user = verifier.call
  rescue Auth::VerifyOtpChallengeToken::InvalidToken => e
    render_auth_error("Invalid or expired challenge: #{e.message}")
  else
    if user.otp_locked?
      return render_auth_error(
        'Account temporarily locked due to too many failed 2FA attempts. Try again in 30 minutes.',
        http_status: :locked
      )
    end

    otp_code = params[:otp_code].to_s.strip
    if user.validate_and_consume_otp!(otp_code) || user.invalidate_otp_backup_code!(otp_code)
      verifier.mark_consumed!
      user.reset_failed_otp_attempts!
      render_auth_success(user)
    else
      user.register_failed_otp_attempt!
      render_auth_error('Invalid two-factor code')
    end
  end
end
