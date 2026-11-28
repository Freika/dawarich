# frozen_string_literal: true

class Api::V1::Auth::GoogleController < Api::V1::Auth::OauthController
  PROVIDER = 'google_oauth2'
  LOCALE_SCOPE = 'google'

  private

  def token_verifier
    Auth::VerifyGoogleToken
  end

  def provider_label
    I18n.t('oauth_providers.google')
  end
end
