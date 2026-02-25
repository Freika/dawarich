# frozen_string_literal: true

module Omniauthable
  extend ActiveSupport::Concern

  class_methods do
    def from_omniauth(access_token)
      data = access_token.info
      provider = access_token.provider
      uid = access_token.uid

      # First, try to find user by provider and uid (for linked accounts)
      user = find_by(provider: provider, uid: uid)

      return user if user

      # If not found, try to find by email
      user = find_by(email: data['email']) if data['email'].present?

      if user
        # Update provider and uid for existing user (first-time linking)
        user.update!(provider: provider, uid: uid)

        return user
      end

      # Check if auto-registration is allowed for OIDC
      return nil if provider == 'openid_connect' && !oidc_auto_register_enabled?

      # Attempt to create user (will fail validation if email is blank)
      create(
        email: data['email'],
        password: Devise.friendly_token[0, 20],
        provider: provider,
        uid: uid
      )
    end

    private

    def oidc_auto_register_enabled?
      OIDC_AUTO_REGISTER
    end
  end
end
