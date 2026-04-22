# frozen_string_literal: true

module GeofenceEvents
  class Record
    # Best-effort dedup: suppresses webhook fan-out for identical (user, area, type)
    # events within a trailing 120s window based on `occurred_at`. This is not a
    # strict correctness guarantee — backwards clock skew from a client and
    # concurrent writers can both defeat it. Webhook consumers should be idempotent.
    DEDUP_WINDOW = 120.seconds

    def self.call(**attrs)
      new(**attrs).call
    end

    def initialize(user:, area:, event_type:, source:, occurred_at:, lonlat:,
                   accuracy_m: nil, device_id: nil, metadata: {})
      @user = user
      @area = area
      @event_type = event_type
      @source = source
      @occurred_at = occurred_at
      @lonlat = lonlat
      @accuracy_m = accuracy_m
      @device_id = device_id
      @metadata = metadata
    end

    def call
      event = create_event
      safely_apply_state(event)
      fan_out_webhooks(event) unless duplicate_within_window?(event)
      event
    end

    private

    def safely_apply_state(event)
      Evaluator::StateStore.apply(@user, @area, @event_type)
    rescue Redis::BaseError => e
      Sentry.capture_exception(e, extra: { user_id: @user.id, area_id: @area.id, event_id: event.id })
    end

    def create_event
      GeofenceEvent.create!(
        user: @user,
        area: @area,
        event_type: @event_type,
        source: @source,
        occurred_at: @occurred_at,
        received_at: Time.current,
        lonlat: @lonlat,
        accuracy_m: @accuracy_m,
        device_id: @device_id,
        metadata: @metadata
      )
    end

    def duplicate_within_window?(event)
      GeofenceEvent
        .where(user_id: @user.id, area_id: @area.id, event_type: event.event_type)
        .where.not(id: event.id)
        .where('occurred_at >= ?', event.occurred_at - DEDUP_WINDOW)
        .exists?
    end

    def fan_out_webhooks(event)
      @user.webhooks.where(active: true).find_each do |webhook|
        next unless webhook.subscribed_to?(area: @area, event_type: @event_type.to_s)

        delivery = WebhookDelivery.create!(webhook: webhook, geofence_event: event, status: :pending)
        Webhooks::DeliverJob.perform_later(delivery.id)
      end
    end
  end
end
