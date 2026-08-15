# frozen_string_literal: true

class Users::OtpChallengeController < ApplicationController
  include PendingImportClaimable

  OTP_CHALLENGE_TTL = 5.minutes
  MAX_FAILED_ATTEMPTS = 5

  def create
    user = User.find_by(id: session[:otp_user_id])

    unless user && otp_challenge_valid?
      clear_otp_session
      redirect_to new_user_session_path,
                  alert: I18n.t('controllers.users.otp_challenge.session_expired_please_sign_in_again')
      return
    end

    otp_code = params[:otp_attempt]

    if authenticate_otp(user, otp_code)
      clear_otp_session
      user.reset_failed_otp_attempts!
      sign_in(user)
      redirect_to after_sign_in_path_for(user), notice: I18n.t('controllers.users.otp_challenge.signed_in_successfully')
    elsif user.otp_locked?
      clear_otp_session
      alert = I18n.t('controllers.users.otp_challenge.account_temporarily_locked_due_to_too_many_failed_2fa_attempts')
      redirect_to new_user_session_path,
                  alert: alert
    else
      user.register_failed_otp_attempt!

      session[:otp_failed_attempts] = (session[:otp_failed_attempts] || 0) + 1
      if session[:otp_failed_attempts] >= MAX_FAILED_ATTEMPTS
        clear_otp_session
        alert = I18n.t('controllers.users.otp_challenge.too_many_invalid_two_factor_codes_please_sign_in_again')
        redirect_to new_user_session_path,
                    alert: alert
        return
      end

      flash.now[:alert] = I18n.t('controllers.users.otp_challenge.invalid_two_factor_code')
      render 'devise/sessions/otp_challenge', status: :unprocessable_entity
    end
  end

  protected

  def after_sign_in_path_for(resource)
    claim_pending_import_for(resource)
    super
  end

  private

  def authenticate_otp(user, otp_code)
    return user.invalidate_otp_backup_code!(otp_code) if user.otp_locked?

    user.validate_and_consume_otp!(otp_code) || user.invalidate_otp_backup_code!(otp_code)
  end

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
