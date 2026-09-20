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
      flash.now[:alert] = I18n.t('controllers.settings.two_factor.invalid_verification_code')
      render :verify, status: :unprocessable_entity
    end
  end

  def destroy
    unless current_user.valid_password?(params[:password])
      redirect_to settings_two_factor_path, alert: I18n.t('controllers.settings.two_factor.incorrect_password')
      return
    end

    otp_code = params[:otp_attempt].to_s
    otp_ok = current_user.validate_and_consume_otp!(otp_code) ||
             current_user.invalidate_otp_backup_code!(otp_code)

    unless otp_ok
      redirect_to settings_two_factor_path,
                  alert: I18n.t('controllers.settings.two_factor.provide_a_valid_two_factor_code_or_backup_code_to')
      return
    end

    current_user.update!(
      otp_required_for_login: false,
      otp_secret: nil,
      otp_backup_codes: nil
    )
    redirect_to settings_two_factor_path,
                notice: I18n.t('controllers.settings.two_factor.two_factor_authentication_disabled')
  end

  private

  def require_two_factor_available
    return if DawarichSettings.two_factor_available?

    alert = I18n.t('controllers.settings.two_factor.two_factor_authentication_is_not_configured_on_this_instance')
    redirect_to settings_general_index_path,
                alert: alert
  end

  def generate_qr_code
    uri = current_user.otp_provisioning_uri(current_user.email, issuer: 'Dawarich')
    ResponsiveQrSvg.call(uri)
  end
end
