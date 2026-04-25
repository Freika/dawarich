# frozen_string_literal: true

class Api::V1::Users::TwoFactorController < ApiController
  before_action :ensure_two_factor_available
  before_action :ensure_credential_provided, only: %i[backup_codes destroy]
  # `confirm` enables 2FA on the account using the OTP that was just provisioned
  # in `setup`. Because the user has not yet enrolled an authenticator from the
  # account owner's perspective, the OTP itself cannot serve as a credential —
  # an attacker holding only the API key could call setup (provisioning a secret
  # to their own authenticator) and then confirm with a valid OTP. Require a
  # fresh password re-auth before flipping the otp_required flag.
  before_action :ensure_password_provided, only: :confirm

  def setup
    current_api_user.otp_secret = User.generate_otp_secret if current_api_user.otp_secret.blank?
    current_api_user.save!

    render json: {
      provisioning_uri: current_api_user.otp_provisioning_uri(current_api_user.email, issuer: 'Dawarich'),
      secret: current_api_user.otp_secret
    }
  end

  def confirm
    if current_api_user.otp_secret.present? &&
       ROTP::TOTP.new(current_api_user.otp_secret).verify(params[:otp_code].to_s, drift_behind: 30)
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

  def ensure_credential_provided
    return if valid_otp? || valid_password?

    render json: { error: 'credential_required', message: 'Provide a valid OTP or password.' },
           status: :unauthorized
  end

  def ensure_password_provided
    return if valid_password?

    render json: { error: 'password_required', message: 'Provide your current password.' },
           status: :unauthorized
  end

  def valid_otp?
    return false if params[:otp_code].blank?
    return false if current_api_user.otp_secret.blank?

    ROTP::TOTP.new(current_api_user.otp_secret).verify(params[:otp_code].to_s, drift_behind: 30).present?
  end

  def valid_password?
    params[:password].present? && current_api_user.valid_password?(params[:password])
  end
end
