# frozen_string_literal: true

module GeofenceEvents
  class Record
    def self.call(**)
      new(**).call
    end

    def initialize(user:, place:, event_type:, source:, occurred_at:, lonlat:, accuracy_m: nil, device_id: nil,
                   metadata: {}, apply_state: true)
      @user = user
      @place = place
      @event_type = event_type.to_s
      @source = source.to_s
      @occurred_at = occurred_at
      @lonlat = lonlat
      @accuracy_m = accuracy_m
      @device_id = device_id
      @metadata = metadata
      @apply_state = apply_state
    end

    def call
      return unless record?

      event = create_event
      fan_out(event)
      event
    end

    private

    DUPLICATE_WINDOW = 120.seconds

    def record?
      return !already_recorded? unless @apply_state

      store = StateStore.new(@user)
      @event_type == 'enter' ? store.enter!(@place.id) : store.leave!(@place.id)
    rescue StateStore::Unavailable => e
      ExceptionReporter.call(e, 'Geofence state unavailable')
      @source == 'native_app'
    end

    def already_recorded?
      GeofenceEvent.real.where(user: @user, place: @place, event_type: @event_type)
                   .where(occurred_at: (@occurred_at - DUPLICATE_WINDOW)..(@occurred_at + DUPLICATE_WINDOW))
                   .exists?
    end

    def create_event
      received_at = Time.current
      GeofenceEvent.create!(
        user: @user, place: @place, place_name: @place.name, event_type: @event_type, source: @source,
        occurred_at: @occurred_at, received_at:, lonlat: @lonlat,
        accuracy_m: @accuracy_m, device_id: @device_id, metadata: @metadata,
        webhook_skip_reason: webhook_skip_reason(received_at)
      )
    end

    def webhook_skip_reason(received_at)
      return :late if received_at - @occurred_at > GeofenceEvent::WEBHOOK_FRESHNESS

      :throttled if hourly_limit_reached?
    end

    def hourly_limit_reached?
      return false unless @user.entitlements.webhook_limits?

      GeofenceEvent.real.where(user: @user, webhook_skip_reason: nil, occurred_at: 1.hour.ago..)
                   .count >= GeofenceEvent::WEBHOOK_HOURLY_LIMIT
    end

    def fan_out(event)
      return if event.webhook_skip_reason || !@user.entitlements.pro_api?

      @user.webhooks.where(active: true).find_each do |webhook|
        next unless webhook.subscribed_to?(place: @place, event_type: @event_type)

        delivery = WebhookDelivery.create!(webhook:, geofence_event: event)
        Webhooks::DeliverJob.perform_later(delivery.id)
      end
    end
  end
end
