# frozen_string_literal: true

class Api::V1::Users::TwoFactorController < ApiController
  TOTP_DRIFT = 1

  before_action :ensure_two_factor_available
  before_action :ensure_password_provided, only: %i[setup confirm backup_codes destroy]
  before_action :ensure_otp_or_backup_provided, only: %i[destroy]

  def setup
    if current_api_user.otp_required_for_login?
      render json: { error: 'two_factor_already_enabled',
                     message: 'Disable 2FA first to re-provision the secret.' },
             status: :conflict
      return
    end

    current_api_user.otp_secret = User.generate_otp_secret
    current_api_user.save!

    render json: {
      provisioning_uri: current_api_user.otp_provisioning_uri(current_api_user.email, issuer: 'Dawarich'),
      secret: current_api_user.otp_secret
    }
  end

  def confirm
    if current_api_user.otp_secret.present? &&
       ROTP::TOTP.new(current_api_user.otp_secret)
                 .verify(params[:otp_code].to_s, drift_behind: TOTP_DRIFT, drift_ahead: TOTP_DRIFT)
      current_api_user.otp_required_for_login = true
      codes = current_api_user.generate_otp_backup_codes!
      current_api_user.save!
      render json: { backup_codes: codes }
    else
      render json: { error: 'invalid_otp' }, status: :unprocessable_content
    end
  end

  def backup_codes
    codes = current_api_user.generate_otp_backup_codes!
    current_api_user.save!
    render json: { backup_codes: codes }
  end

  def destroy
    current_api_user.update!(
      otp_secret: nil,
      otp_required_for_login: false,
      otp_backup_codes: []
    )
    render json: { message: 'Two-factor authentication disabled' }
  end

  private

  def ensure_two_factor_available
    return if DawarichSettings.two_factor_available?

    render json: { error: 'two_factor_not_available' }, status: :service_unavailable
  end

  # audit M-1: disabling 2FA must require both factors. Previously this
  # before_action accepted password OR otp; with that, a leaked password
  # alone removed the second factor on its way to a takeover.
  def ensure_otp_or_backup_provided
    return if consume_otp_or_backup!

    render json: { error: 'otp_required',
                   message: 'Provide a valid two-factor code (or backup code) to disable 2FA.' },
           status: :unauthorized
  end

  def ensure_password_provided
    return if valid_password?

    render json: { error: 'password_required', message: 'Provide your current password.' },
           status: :unauthorized
  end

  def consume_otp_or_backup!
    code = params[:otp_code].to_s
    return false if code.blank?

    current_api_user.validate_and_consume_otp!(code) ||
      current_api_user.invalidate_otp_backup_code!(code)
  end

  def valid_password?
    params[:password].present? && current_api_user.valid_password?(params[:password])
  end
end
