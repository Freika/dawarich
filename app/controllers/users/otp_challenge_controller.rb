# frozen_string_literal: true

class Users::OtpChallengeController < ApplicationController
  OTP_CHALLENGE_TTL = 5.minutes

  def create
    user = User.find_by(id: session[:otp_user_id])

    unless user && otp_challenge_valid?
      clear_otp_session
      redirect_to new_user_session_path, alert: 'Session expired. Please sign in again.'
      return
    end

    if user.otp_locked?
      clear_otp_session
      redirect_to new_user_session_path,
                  alert: 'Account temporarily locked due to too many failed 2FA attempts. Try again in 30 minutes or reset your password.'
      return
    end

    otp_code = params[:otp_attempt]

    if user.validate_and_consume_otp!(otp_code) || user.invalidate_otp_backup_code!(otp_code)
      clear_otp_session
      user.reset_failed_otp_attempts!
      sign_in(user)
      redirect_to after_sign_in_path_for(user), notice: 'Signed in successfully.'
    else
      user.register_failed_otp_attempt!
      flash.now[:alert] = 'Invalid two-factor code.'
      render 'devise/sessions/otp_challenge', status: :unprocessable_entity
    end
  end

  private

  def otp_challenge_valid?
    challenge_at = session[:otp_challenge_at]
    challenge_at.present? && Time.zone.at(challenge_at) > OTP_CHALLENGE_TTL.ago
  end

  def clear_otp_session
    session.delete(:otp_user_id)
    session.delete(:otp_challenge_at)
  end
end
