# frozen_string_literal: true

class Users::OtpChallengeController < ApplicationController
  def create
    user = User.find_by(id: session[:otp_user_id])

    unless user
      redirect_to new_user_session_path, alert: 'Session expired. Please sign in again.'
      return
    end

    otp_code = params[:otp_attempt]

    if user.validate_and_consume_otp!(otp_code) || user.invalidate_otp_backup_code!(otp_code)
      session.delete(:otp_user_id)
      sign_in(user)
      redirect_to after_sign_in_path_for(user), notice: 'Signed in successfully.'
    else
      flash.now[:alert] = 'Invalid two-factor code.'
      render 'devise/sessions/otp_challenge', status: :unprocessable_entity
    end
  end
end
