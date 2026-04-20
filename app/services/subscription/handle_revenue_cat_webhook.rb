# frozen_string_literal: true

class Subscription::HandleRevenueCatWebhook
  class UnknownUser < StandardError; end

  PRODUCT_TO_PLAN = {
    'dawarich.lite.yearly' => :lite,
    'dawarich.pro.yearly' => :pro,
    'dawarich.pro.monthly' => :pro
  }.freeze

  STORE_TO_SOURCE = {
    'APP_STORE' => :apple_iap,
    'PLAY_STORE' => :google_play
  }.freeze

  def initialize(payload)
    @event = payload.fetch('event', {})
  end

  def call
    case @event['type']
    when 'INITIAL_PURCHASE', 'TRIAL_STARTED'
      apply_trial_or_purchase
    when 'RENEWAL', 'NON_RENEWING_PURCHASE'
      apply_renewal
    when 'EXPIRATION'
      apply_expiration
    when 'CANCELLATION'
      # Intent to not renew. No immediate status change; EXPIRATION handles the demotion.
      nil
    when 'PRODUCT_CHANGE'
      apply_plan_change
    else
      # Unknown event type: no-op. Log and move on.
      Rails.logger.info("[RevenueCat webhook] ignoring unknown event type: #{@event['type']}")
    end
  end

  private

  def user
    @user ||= User.find_by(id: @event['app_user_id']).tap do |u|
      raise UnknownUser, "No user with id=#{@event['app_user_id']}" unless u
    end
  end

  def apply_trial_or_purchase
    return if conflict_with_paddle?

    user.update!(
      status: :trial,
      plan: plan_from_product,
      subscription_source: source_from_store,
      active_until: expiration_time
    )
  end

  def apply_renewal
    return if conflict_with_paddle?

    user.update!(
      status: :active,
      plan: plan_from_product,
      subscription_source: source_from_store,
      active_until: expiration_time
    )
  end

  def apply_expiration
    return unless user.subscription_source.to_sym == source_from_store
    # Only expire if our source matches — don't demote a paddle sub based on an IAP expiration event.

    user.update!(status: :inactive, active_until: expiration_time)
  end

  def apply_plan_change
    return if conflict_with_paddle?

    user.update!(plan: plan_from_product, active_until: expiration_time)
  end

  # If user has an active Paddle sub, IAP events must not overwrite it.
  def conflict_with_paddle?
    return false unless user.subscription_source.to_s == 'paddle'
    return false unless user.active_until&.future?

    Rails.logger.warn(
      "[RevenueCat webhook] refusing to overwrite active paddle sub for user=#{user.id}, event=#{@event['type']}"
    )
    true
  end

  def plan_from_product
    PRODUCT_TO_PLAN.fetch(@event['product_id'], :lite)
  end

  def source_from_store
    STORE_TO_SOURCE.fetch(@event['store'], :apple_iap)
  end

  def expiration_time
    ms = @event['expiration_at_ms']
    return nil if ms.nil?

    Time.zone.at(ms.to_i / 1000)
  end
end
