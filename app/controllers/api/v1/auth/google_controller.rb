# frozen_string_literal: true

class Api::V1::Auth::GoogleController < Api::V1::Auth::BaseController
  PROVIDER = 'google_oauth2'
  def create
    claims =
      begin
        Auth::VerifyGoogleToken.new(params[:id_token], nonce: params[:nonce]).call
      rescue Auth::VerifyGoogleToken::InvalidToken => e
        return render_auth_error(I18n.t('controllers.api.v1.auth.google.token_verification_failed', message: e.message))
      end

    user, created = Auth::FindOrCreateOauthUser.new(
      provider: PROVIDER,
      provider_label: I18n.t('oauth_providers.google'),
      claims: claims,
      email_verified: email_verified?(claims)
    ).call

    render_auth_success(user, status: created ? :created : :ok)
  rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
    render json: {
      error: 'email_not_verified',
      message: I18n.t('controllers.api.v1.auth.google.google_has_not_verified_this_email_sign_in_with_password')
    }, status: :forbidden
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
    render json: {
      error: 'verification_sent',
      message: I18n.t('controllers.api.v1.auth.google.this_email_already_has_a_dawarich_account_we_sent_a')
    }, status: :accepted
  rescue Auth::FindOrCreateOauthUser::AccountPendingDeletion
    render json: {
      error: 'account_pending_deletion',
      message: I18n.t('controllers.api.v1.auth.account_pending_deletion')
    }, status: :conflict
  end

  private

  # Google sends email_verified as a boolean (or string in some flows).
  def email_verified?(claims)
    [true, 'true'].include?(claims[:email_verified])
  end
end
