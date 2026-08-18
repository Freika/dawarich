# frozen_string_literal: true

class Api::V1::Auth::AppleController < Api::V1::Auth::BaseController
  PROVIDER = 'apple'
  def create
    claims =
      begin
        Auth::VerifyAppleToken.new(params[:id_token], nonce: params[:nonce]).call
      rescue Auth::VerifyAppleToken::InvalidToken => e
        return render_auth_error(I18n.t('controllers.api.v1.auth.apple.token_verification_failed', message: e.message))
      end

    user, created = Auth::FindOrCreateOauthUser.new(
      provider: PROVIDER,
      provider_label: I18n.t('oauth_providers.sign_in_with_apple'),
      claims: claims,
      email_verified: email_verified?(claims)
    ).call

    render_auth_success(user, status: created ? :created : :ok)
  rescue Auth::FindOrCreateOauthUser::UnverifiedEmail
    render json: {
      error: 'email_not_verified',
      message: I18n.t('controllers.api.v1.auth.apple.apple_has_not_verified_this_email_sign_in_with_password')
    }, status: :forbidden
  rescue Auth::FindOrCreateOauthUser::LinkVerificationSent
    render json: {
      error: 'verification_sent',
      message: I18n.t('controllers.api.v1.auth.apple.this_email_already_has_a_dawarich_account_we_sent_a')
    }, status: :accepted
  rescue Auth::FindOrCreateOauthUser::MissingOauthEmail => e
    Rails.logger.warn("apple.auth.missing_email uid=#{e.uid}")
    render json: {
      error: 'apple_email_missing',
      message: I18n.t('controllers.api.v1.auth.apple.we_couldn_t_find_your_existing_account_and_apple_didn')
    }, status: :unprocessable_entity
  end

  private

  # Apple sends email_verified as a string 'true'/'false' in id_tokens.
  def email_verified?(claims)
    [true, 'true'].include?(claims[:email_verified])
  end
end
