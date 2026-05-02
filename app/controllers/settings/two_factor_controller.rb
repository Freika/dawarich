# frozen_string_literal: true

class Settings::TwoFactorController < ApplicationController
  before_action :authenticate_user!
  before_action :require_two_factor_available

  def show; end

  def create
    current_user.otp_secret = User.generate_otp_secret
    current_user.save!

    @qr_code = generate_qr_code
    @otp_secret = current_user.otp_secret

    render :verify
  end

  def verify
    if current_user.validate_and_consume_otp!(params[:otp_attempt])
      current_user.otp_required_for_login = true
      @backup_codes = current_user.generate_otp_backup_codes!
      current_user.save!

      render :backup_codes
    else
      @qr_code = generate_qr_code
      @otp_secret = current_user.otp_secret
      flash.now[:alert] = 'Invalid verification code. Please try again.'
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    # audit M-1: disabling 2FA must require both factors so a leaked password
    # alone can't strip the second factor before the attacker uses it.
    unless current_user.valid_password?(params[:password])
      redirect_to settings_two_factor_path, alert: 'Incorrect password.'
      return
    end

    otp_code = params[:otp_attempt].to_s
    otp_ok = current_user.validate_and_consume_otp!(otp_code) ||
             current_user.invalidate_otp_backup_code!(otp_code)

    unless otp_ok
      redirect_to settings_two_factor_path,
                  alert: 'Provide a valid two-factor code (or backup code) to disable 2FA.'
      return
    end

    current_user.update!(
      otp_required_for_login: false,
      otp_secret: nil,
      otp_backup_codes: nil
    )
    redirect_to settings_two_factor_path, notice: 'Two-factor authentication disabled.'
  end

  private

  def require_two_factor_available
    return if DawarichSettings.two_factor_available?

    redirect_to settings_general_index_path, alert: 'Two-factor authentication is not configured on this instance.'
  end

  def generate_qr_code
    uri = current_user.otp_provisioning_uri(current_user.email, issuer: 'Dawarich')
    qrcode = RQRCode::QRCode.new(uri)
    qrcode.as_svg(
      color: '000',
      fill: 'fff',
      shape_rendering: 'crispEdges',
      module_size: 6,
      standalone: true,
      use_path: true,
      offset: 5
    )
  end
end
