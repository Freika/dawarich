# frozen_string_literal: true

module Webhooks
  class PayloadBuilder
    def self.call(event)
      area = event.area
      {
        id: event.id,
        type: event.event_type,
        area: {
          id: area.id, name: area.name,
          latitude: area.latitude.to_f, longitude: area.longitude.to_f, radius: area.radius
        },
        user_id: event.user_id,
        source: event.source,
        occurred_at: event.occurred_at.utc.iso8601,
        received_at: event.received_at.utc.iso8601,
        location: { latitude: event.lonlat.y, longitude: event.lonlat.x, accuracy_m: event.accuracy_m },
        device_id: event.device_id,
        metadata: event.metadata
      }
    end
  end
end
