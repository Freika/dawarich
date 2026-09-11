# frozen_string_literal: true

class Families::LocationRequestPushJob < ApplicationJob
  queue_as :default
  sidekiq_options retry: false
  retry_on Families::PushNotification::DeliveryError, wait: ->(attempt) { [60, attempt**4].max.seconds }, attempts: 4

  def perform(request_id, subscription_id = nil)
    return unless PushSubscription.delivery_enabled?

    request = Family::LocationRequest.active.find_by(id: request_id)
    return unless request && eligible?(request)

    if subscription_id.nil?
      PushSubscription.where(user_id: request.target_user_id).find_each do |subscription|
        self.class.perform_later(request_id, subscription.id)
      end
      return
    end

    subscription = PushSubscription.find_by(id: subscription_id, user_id: request.target_user_id)
    return unless subscription&.deliverable? && PushSubscription.enabled_providers.include?(subscription.provider)

    send_notification(request, subscription)
  end

  private

  def eligible?(request)
    request.requester&.family&.id == request.family_id && request.target_user&.family&.id == request.family_id &&
      DawarichSettings.family_feature_available_for?(request.target_user) &&
      !request.target_user.family_sharing_enabled?
  end

  def send_notification(request, subscription)
    payload = {
      title: 'Location request',
      body: 'A family member is requesting your location. Open Dawarich to respond.',
      sound: 'default',
      ttl: [request.expires_at.to_i - Time.current.to_i, 3600].min,
      data: { type: 'family_location_request', request_id: request.id, context_id: subscription.context_id,
              user_id: request.target_user_id, installation_id: subscription.installation_id }
    }
    return unless Families::PushNotification.deliver(subscription, payload) == :unregistered

    PushSubscription.where(id: subscription.id, push_token: subscription.push_token,
                           context_id: subscription.context_id, updated_at: subscription.updated_at).delete_all
  end
end
