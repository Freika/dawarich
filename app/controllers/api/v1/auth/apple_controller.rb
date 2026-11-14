# frozen_string_literal: true

class Api::V1::Auth::AppleController < Api::V1::Auth::OauthController
  PROVIDER = 'apple'
  LOCALE_SCOPE = 'apple'

  rescue_from Auth::FindOrCreateOauthUser::MissingOauthEmail do |error|
    Rails.logger.warn("apple.auth.missing_email uid=#{error.uid}")
    render json: {
      error: 'apple_email_missing',
      message: oauth_message(:we_couldn_t_find_your_existing_account_and_apple_didn)
    }, status: :unprocessable_entity
  end

  private

  def token_verifier
    Auth::VerifyAppleToken
  end

  def provider_label
    I18n.t('oauth_providers.sign_in_with_apple')
  end
end
