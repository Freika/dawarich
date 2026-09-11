# frozen_string_literal: true

class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :installation_id, format: { with: /\A[a-zA-Z0-9-]{16,128}\z/ }
  validates :provider, inclusion: { in: %w[apns fcm] }
  validates :environment, inclusion: { in: %w[development production] }, if: -> { provider == 'apns' }
  validates :environment, absence: true, if: -> { provider == 'fcm' }
  validates :push_token, uniqueness: { scope: %i[provider environment] }, length: { maximum: 2048 }
  validates :push_token, format: { with: /\A[0-9a-fA-F]{32,512}\z/ }, if: -> { provider == 'apns' }
  validates :push_token, format: { with: /\A[a-zA-Z0-9_:-]{16,2048}\z/ }, if: -> { provider == 'fcm' }
  validates :api_key_digest, :expires_at, presence: true
  validates :context_id, format: { with: /\A[a-zA-Z0-9-]{16,128}\z/ }

  def self.delivery_enabled?
    enabled_providers.any?
  end

  def self.enabled_providers
    return [] unless ENV['FAMILY_PUSH_ENABLED'] == 'true'

    providers = []
    providers << 'apns' if PushNotifications::Apns.configured?
    providers << 'fcm' if PushNotifications::Fcm.configured?
    providers
  end

  def deliverable?
    expires_at.future? && api_key_digest == Digest::SHA256.hexdigest(user.api_key.to_s)
  end
end
