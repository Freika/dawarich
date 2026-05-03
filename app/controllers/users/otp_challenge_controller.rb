# frozen_string_literal: true

class Users::OtpChallengeController < ApplicationController
  OTP_CHALLENGE_TTL = 5.minutes
  MAX_FAILED_ATTEMPTS = 5

  def create
    user = User.find_by(id: session[:otp_user_id])

    unless user && otp_challenge_valid?
      clear_otp_session
      redirect_to new_user_session_path, alert: 'Session expired. Please sign in again.'
      return
    end

    otp_code = params[:otp_attempt]

    if user.validate_and_consume_otp!(otp_code) || user.invalidate_otp_backup_code!(otp_code)
      clear_otp_session
      sign_in(user)
      redirect_to after_sign_in_path_for(user), notice: 'Signed in successfully.'
    else
      session[:otp_failed_attempts] = (session[:otp_failed_attempts] || 0) + 1
      if session[:otp_failed_attempts] >= MAX_FAILED_ATTEMPTS
        clear_otp_session
        redirect_to new_user_session_path,
                    alert: 'Too many invalid two-factor codes. Please sign in again.'
        return
      end

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
    session.delete(:otp_failed_attempts)
  end
end
