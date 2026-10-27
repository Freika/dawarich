# frozen_string_literal: true

class GeofenceEventSerializer
  def initialize(event)
    @event = event
  end

  def call
    {
      id: @event.id,
      place_id: @event.place_id,
      place_name: @event.display_place_name,
      event_type: @event.event_type,
      source: @event.source,
      occurred_at: @event.occurred_at.utc.iso8601,
      latitude: @event.lonlat.y,
      longitude: @event.lonlat.x,
      accuracy_m: @event.accuracy_m
    }
  end
end
