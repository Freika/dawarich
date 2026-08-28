# frozen_string_literal: true

class Api::V1::Auth::OtpChallengesController < Api::V1::Auth::BaseController
  def create
    verifier = Auth::VerifyOtpChallengeToken.new(params[:challenge_token])
    user = verifier.call
  rescue Auth::VerifyOtpChallengeToken::InvalidToken => e
    render_auth_error(I18n.t('controllers.api.v1.auth.otp_challenges.invalid_challenge', message: e.message))
  else
    otp_code = params[:otp_code].to_s.strip

    if authenticate_otp(user, otp_code)
      verifier.mark_consumed!
      user.reset_failed_otp_attempts!
      render_auth_success(user)
    elsif user.otp_locked?
      render_auth_error(
        I18n.t('controllers.api.v1.auth.otp_challenges.account_locked'),
        http_status: :locked
      )
    else
      user.register_failed_otp_attempt!
      render_auth_error(I18n.t('controllers.api.v1.auth.otp_challenges.invalid_two_factor_code'))
    end
  end

  private

  def authenticate_otp(user, otp_code)
    return user.invalidate_otp_backup_code!(otp_code) if user.otp_locked?

    user.validate_and_consume_otp!(otp_code) || user.invalidate_otp_backup_code!(otp_code)
  end
end
