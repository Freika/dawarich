# frozen_string_literal: true

class Settings::TwoFactorController < ApplicationController
  before_action :authenticate_user!

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
    if current_user.valid_password?(params[:password])
      current_user.update!(
        otp_required_for_login: false,
        otp_secret: nil,
        otp_backup_codes: nil
      )
      redirect_to settings_two_factor_path, notice: 'Two-factor authentication disabled.'
    else
      redirect_to settings_two_factor_path, alert: 'Incorrect password.'
    end
  end

  private

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
