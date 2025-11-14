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

      if user
        # User found by provider/uid
        return user
      end

      # If not found, try to find by email
      user = find_by(email: data['email'])

      if user
        # Update provider and uid for existing user (first-time linking)
        user.update(provider: provider, uid: uid)
        return user
      end

      # Create new user if not found
      user = create(
        email: data['email'],
        password: Devise.friendly_token[0, 20],
        provider: provider,
        uid: uid
      )

      user
    end
  end
end
