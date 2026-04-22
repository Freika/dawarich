# frozen_string_literal: true

class GeofenceEventSerializer
  def initialize(event)
    @event = event
  end

  def call
    {
      id: @event.id,
      area_id: @event.area_id,
      area_name: @event.area.name,
      event_type: @event.event_type,
      source: @event.source,
      occurred_at: @event.occurred_at.utc.iso8601,
      accuracy_m: @event.accuracy_m
    }
  end
end
