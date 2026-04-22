# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Webhooks::PayloadBuilder do
  let(:user) { create(:user) }
  let(:area) { create(:area, user: user, name: 'Home', latitude: 52.5, longitude: 13.4, radius: 100) }
  let(:event) do
    create(:geofence_event,
           user: user,
           area: area,
           event_type: :enter,
           source: :native_app,
           occurred_at: Time.utc(2026, 4, 22, 17, 12, 33),
           lonlat: 'POINT(13.399876 52.500123)',
           accuracy_m: 25,
           device_id: 'ABCD-1234',
           metadata: { os: 'ios-17.4', app_version: '2.1.0' })
  end

  describe '.call' do
    subject(:payload) { described_class.call(event) }

    it 'returns the fixed v1 schema' do
      expect(payload).to match(
        id: event.id,
        type: 'enter',
        area: { id: area.id, name: 'Home', latitude: 52.5, longitude: 13.4, radius: 100 },
        user_id: user.id,
        source: 'native_app',
        occurred_at: '2026-04-22T17:12:33Z',
        location: { latitude: a_value_within(0.001).of(52.500123),
                    longitude: a_value_within(0.001).of(13.399876),
                    accuracy_m: 25 },
        device_id: 'ABCD-1234',
        metadata: { 'os' => 'ios-17.4', 'app_version' => '2.1.0' }
      )
    end
  end
end
