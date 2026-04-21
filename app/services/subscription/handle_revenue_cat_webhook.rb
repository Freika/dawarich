# frozen_string_literal: true

class Subscription::HandleRevenueCatWebhook
  class UnknownUser < StandardError; end
  class UnknownProductId < StandardError; end

  PRODUCT_TO_PLAN = {
    'dawarich.lite.yearly' => :lite,
    'dawarich.pro.yearly' => :pro,
    'dawarich.pro.monthly' => :pro
  }.freeze

  STORE_TO_SOURCE = {
    'APP_STORE' => :apple_iap,
    'PLAY_STORE' => :google_play
  }.freeze

  IDEMPOTENCY_TTL = 7.days

  def initialize(payload)
    @event = payload.fetch('event', {})
  end

  def call
    return :ok if duplicate_event?

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

    mark_processed!
    :ok
  end

  private

  def event_id
    @event_id ||= @event['id'].presence || derived_event_id
  end

  def derived_event_id
    # Fallback for events missing an explicit id - use type + app_user_id + timestamp.
    [@event['type'], @event['app_user_id'], @event['event_timestamp_ms']].compact.join(':')
  end

  def event_timestamp
    ms = @event['event_timestamp_ms'].to_i
    Time.zone.at(ms / 1000.0)
  end

  def idempotency_cache_key
    "rc_webhook:processed:#{event_id}"
  end

  def duplicate_event?
    Rails.cache.exist?(idempotency_cache_key)
  end

  def mark_processed!
    Rails.cache.write(idempotency_cache_key, true, expires_in: IDEMPOTENCY_TTL)
  end

  def user
    @user ||= User.find_by(id: @event['app_user_id']).tap do |u|
      raise UnknownUser, "No user with id=#{@event['app_user_id']}" unless u
    end
  end

  def apply_trial_or_purchase
    return if conflict_with_paddle?

    user.update!(
      status: initial_purchase_status,
      plan: plan_from_product,
      subscription_source: source_from_store,
      active_until: expiration_time
    )
  end

  def initial_purchase_status
    case @event['period_type']
    when 'NORMAL' then :active
    else :trial
    end
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
    # Only expire if our source matches — don't demote a paddle sub based on an IAP expiration event.
    return unless user.subscription_source.to_sym == source_from_store

    # Gate on event_timestamp to ignore stale/out-of-order events.
    current_until = user.active_until || Time.zone.at(0)
    return if event_timestamp <= current_until

    attrs = { status: :inactive }
    # Only clobber active_until if the expiration timestamp is more recent than the current one.
    if expiration_time && (user.active_until.nil? || expiration_time > user.active_until)
      attrs[:active_until] = expiration_time
    end

    user.update!(attrs)
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
    PRODUCT_TO_PLAN.fetch(@event['product_id']) { raise UnknownProductId, @event['product_id'].to_s }
  end

  def source_from_store
    store = @event.fetch('store')
    raise KeyError, 'store' if store.nil?

    STORE_TO_SOURCE.fetch(store) { raise KeyError, "unknown store: #{store}" }
  end

  def expiration_time
    ms = @event['expiration_at_ms']
    return nil if ms.nil?

    Time.zone.at(ms.to_i / 1000)
  end
end
