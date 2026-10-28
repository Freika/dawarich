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
      place = target_place
      return if place.nil?

      delivery = WebhookDelivery.create!(webhook: @webhook, geofence_event: synthetic_event(place))
      Webhooks::DeliverJob.perform_later(delivery.id)
      delivery
    end

    private

    def target_place
      places = @webhook.user.places.monitored_geofences.order(:id)
      (@webhook.place_ids.any? ? places.where(id: @webhook.place_ids) : places).first
    end

    def synthetic_event(place)
      now = Time.current
      GeofenceEvent.create!(
        user: @webhook.user, place:, place_name: place.name, synthetic: true, source: :native_app,
        event_type: @webhook.event_types.include?(Webhook::EVENT_TYPES['enter']) ? :enter : :leave,
        occurred_at: now, received_at: now, metadata: { 'test' => true },
        lonlat: "POINT(#{place.lon} #{place.lat})"
      )
    end
  end
end
