# frozen_string_literal: true

module Webhooks
  class PayloadBuilder
    def self.call(event)
      place = event.place
      {
        id: event.id,
        type: event.event_type,
        place: {
          id: event.place_id, name: event.display_place_name,
          latitude: place&.lat, longitude: place&.lon, radius: place&.visit_radius
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
