# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Traccar upstream client nested payload', type: :request do
  let(:user) { create(:user) }

  let(:payload) do
    {
      device_id: 'phone_traccar',
      location: {
        coords: {
          accuracy: 14.26,
          altitude: 81.2,
          heading: 90.03,
          latitude: 52.52,
          longitude: 13.405,
          speed: 0.34
        },
        battery: { is_charging: false, level: 0.47 },
        activity: { type: 'still' },
        extras: {},
        is_moving: false,
        manual: true,
        odometer: 260.03,
        timestamp: '2026-05-28T18:59:59.929Z'
      }
    }
  end

  it 'ingests a point sent by the upstream traccar-client' do
    expect do
      post "/api/v1/traccar/points?api_key=#{user.api_key}", params: payload, as: :json
    end.to change(Point, :count).by(1)

    expect(response).to have_http_status(:ok)

    point = Point.last
    expect(point.lon.to_f).to be_within(0.0001).of(13.405)
    expect(point.lat.to_f).to be_within(0.0001).of(52.52)
    expect(point.battery).to eq(47)
    expect(point.battery_status).to eq('unplugged')
    expect(point.tracker_id).to eq('phone_traccar')
    expect(point.motion_data).to include('activity' => 'still', 'is_moving' => false)
  end
end
