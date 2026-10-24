# frozen_string_literal: true

module GeofenceEvents
  class SendTest
    def self.call(webhook)
      new(webhook).call
    end

    def initialize(webhook)
      @webhook = webhook
    end

    def call
      area = target_area
      return if area.nil?

      delivery = WebhookDelivery.create!(webhook: @webhook, geofence_event: synthetic_event(area))
      Webhooks::DeliverJob.perform_later(delivery.id)
      delivery
    end

    private

    def target_area
      areas = @webhook.user.areas.order(:id)
      (@webhook.area_ids.any? ? areas.where(id: @webhook.area_ids) : areas).first
    end

    def synthetic_event(area)
      now = Time.current
      GeofenceEvent.create!(
        user: @webhook.user, area:, synthetic: true, source: :native_app,
        event_type: @webhook.event_types.include?(Webhook::EVENT_TYPES['enter']) ? :enter : :leave,
        occurred_at: now, received_at: now, metadata: { 'test' => true },
        lonlat: "POINT(#{area.longitude} #{area.latitude})"
      )
    end
  end
end
