# frozen_string_literal: true

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include PendingImportClaimable

  def github
    handle_auth(I18n.t('oauth_providers.github'))
  end

  def google_oauth2
    handle_auth(I18n.t('oauth_providers.google'))
  end

  def openid_connect
    handle_auth(I18n.t('oauth_providers.openid_connect'))
  end

  def failure
    error_type = request.env['omniauth.error.type']
    error = request.env['omniauth.error']

    # Provide user-friendly error messages
    error_message =
      case error_type
      when :invalid_credentials
        I18n.t('controllers.users.omniauth_callbacks.invalid_credentials')
      when :timeout
        I18n.t('controllers.users.omniauth_callbacks.connection_timeout')
      when :csrf_detected
        I18n.t('controllers.users.omniauth_callbacks.security_error')
      else
        if error&.message&.include?('Discovery')
          I18n.t('controllers.users.omniauth_callbacks.provider_unavailable')
        elsif error&.message&.include?('Issuer mismatch')
          I18n.t('controllers.users.omniauth_callbacks.provider_configuration_error')
        else
          detail = params[:message] || error&.message || I18n.t('controllers.users.omniauth_callbacks.unknown_error')
          I18n.t('controllers.users.omniauth_callbacks.authentication_failed', detail:)
        end
      end

    redirect_to root_path, alert: error_message
  end

  protected

  def after_sign_in_path_for(resource)
    claim_pending_import_for(resource)
    super
  end

  private

  def handle_auth(provider)
    @user = User.from_omniauth(request.env['omniauth.auth'])

    if @user&.persisted?
      # from_omniauth both finds and creates, so only a record born in this
      # request is a signup — otherwise a returning customer arriving through a
      # different affiliate link would be re-credited to the wrong partner.
      attribute_partnero_signup(@user) if @user.oauth_newly_created

      # A 2FA-enabled account must still clear the second factor on OAuth sign-in,
      # mirroring Users::SessionsController#check_otp_required on the password path.
      return stage_otp_challenge(@user) if DawarichSettings.two_factor_available? && @user.otp_required_for_login?

      flash[:notice] = I18n.t 'devise.omniauth_callbacks.success', kind: provider
      sign_in_and_redirect @user, event: :authentication
    elsif @user.nil?
      # User creation was rejected (e.g., OIDC auto-register disabled)
      error_message = if provider == I18n.t('oauth_providers.openid_connect') && !oidc_auto_register_enabled?
                        I18n.t('controllers.users.omniauth_callbacks.oidc_account_requires_administrator')
                      else
                        I18n.t('controllers.users.omniauth_callbacks.account_creation_failed')
                      end
      redirect_to root_path, alert: error_message
    else
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join("\n")
    end
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent => e
    session[:pending_oauth_link] = {
      'user_id' => e.user.id,
      'provider' => e.provider,
      'uid' => e.uid,
      'provider_label' => provider,
      'expires_at' => 15.minutes.from_now.to_i
    }
    redirect_to auth_account_link_challenge_path
  rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
    redirect_to new_user_session_path,
                alert: I18n.t('controllers.users.omniauth_callbacks.email_not_verified', provider:)
  rescue Auth::FindOrCreateOauthUser::AccountPendingDeletion
    redirect_to new_user_session_path,
                alert: I18n.t('controllers.users.omniauth_callbacks.account_pending_deletion')
  end

  def oidc_auto_register_enabled?
    OIDC_AUTO_REGISTER
  end

  # Stage the OTP challenge instead of completing the sign-in, reusing the same
  # session handshake that Users::OtpChallengeController consumes.
  def stage_otp_challenge(user)
    session[:otp_user_id] = user.id
    session[:otp_challenge_at] = Time.current.to_i
    self.resource = user
    switch_locale { render 'devise/sessions/otp_challenge', status: :unprocessable_entity }
  end
end
