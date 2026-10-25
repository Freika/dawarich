# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::PayloadBuilder do
  it 'describes the event, its place and where it happened' do
    place = create(:place, :geofence, name: 'Home', latitude: 52.5, longitude: 13.4, visit_radius: 100)
    event = create(:geofence_event, user: place.user, place:, event_type: :leave, source: :server_inferred,
                                    occurred_at: Time.utc(2026, 10, 24, 12),
                                    received_at: Time.utc(2026, 10, 24, 12, 0, 40), lonlat: 'POINT(13.41 52.51)',
                                    accuracy_m: 12, device_id: 'phone', metadata: { 'battery' => 80 })

    expect(described_class.call(event)).to eq(
      id: event.id,
      type: 'leave',
      place: { id: place.id, name: 'Home', latitude: 52.5, longitude: 13.4, radius: 100 },
      user_id: place.user_id,
      source: 'server_inferred',
      occurred_at: '2026-10-24T12:00:00Z',
      received_at: '2026-10-24T12:00:40Z',
      location: { latitude: 52.51, longitude: 13.41, accuracy_m: 12 },
      device_id: 'phone',
      metadata: { 'battery' => 80 }
    )
  end
end
