# frozen_string_literal: true

module Omniauthable
  extend ActiveSupport::Concern

  class_methods do
    def from_omniauth(access_token)
      provider = access_token.provider.to_s

      if provider == 'openid_connect' && !oidc_auto_register_enabled?
        return User.find_by(provider: provider, uid: access_token.uid.to_s)
      end

      user, _created = Auth::FindOrCreateOauthUser.new(
        provider: provider,
        provider_label: omniauth_provider_label(provider),
        claims: { sub: access_token.uid.to_s, email: access_token.info&.email.to_s },
        email_verified: omniauth_email_verified?(access_token)
      ).call

      user
    end

    private

    def omniauth_email_verified?(access_token)
      raw = access_token.extra&.raw_info

      case access_token.provider.to_s
      when 'google_oauth2', 'openid_connect'
        return false unless raw

        raw['email_verified'] == true || raw[:email_verified] == true
      when 'github'
        access_token.info&.email.to_s.present?
      else
        false
      end
    end

    def omniauth_provider_label(provider)
      case provider
      when 'google_oauth2' then 'Google'
      when 'github' then 'GitHub'
      when 'openid_connect' then OIDC_PROVIDER_NAME
      else provider.to_s.titleize
      end
    end

    def oidc_auto_register_enabled?
      OIDC_AUTO_REGISTER
    end
  end
end
