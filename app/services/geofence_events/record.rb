# frozen_string_literal: true

module GeofenceEvents
  class Record
    def self.call(**)
      new(**).call
    end

    def initialize(user:, area:, event_type:, source:, occurred_at:, lonlat:, accuracy_m: nil, device_id: nil,
                   metadata: {}, apply_state: true)
      @user = user
      @area = area
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
      @event_type == 'enter' ? store.enter!(@area.id) : store.leave!(@area.id)
    rescue StateStore::Unavailable => e
      ExceptionReporter.call(e, 'Geofence state unavailable')
      @source == 'native_app'
    end

    def already_recorded?
      GeofenceEvent.real.where(user: @user, area: @area, event_type: @event_type)
                   .where(occurred_at: (@occurred_at - DUPLICATE_WINDOW)..(@occurred_at + DUPLICATE_WINDOW))
                   .exists?
    end

    def create_event
      GeofenceEvent.create!(
        user: @user, area: @area, event_type: @event_type, source: @source,
        occurred_at: @occurred_at, received_at: Time.current, lonlat: @lonlat,
        accuracy_m: @accuracy_m, device_id: @device_id, metadata: @metadata
      )
    end

    def fan_out(event)
      return unless @user.entitlements.pro_api?

      @user.webhooks.where(active: true).find_each do |webhook|
        next unless webhook.subscribed_to?(area: @area, event_type: @event_type)

        delivery = WebhookDelivery.create!(webhook:, geofence_event: event)
        Webhooks::DeliverJob.perform_later(delivery.id)
      end
    end
  end
end
