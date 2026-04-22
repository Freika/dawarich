# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/points/transitions', type: :request do
  let(:user) { create(:user) }
  let(:area) { create(:area, user: user, latitude: 52.5, longitude: 13.4, radius: 100) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}", 'CONTENT_TYPE' => 'application/json' } }

  def payload(**overrides)
    {
      area_id: area.id,
      event_type: 'enter',
      occurred_at: Time.current.iso8601,
      lonlat: [13.4, 52.5],
      accuracy_m: 25,
      device_id: 'ABCD',
      metadata: { os: 'ios-17.4', app_version: '2.1.0' }
    }.merge(overrides).to_json
  end

  before { GeofenceEvents::Evaluator::StateStore.reset!(user) }

  it 'creates a GeofenceEvent from the native app' do
    post '/api/v1/points/transitions', params: payload, headers: headers
    expect(response).to have_http_status(:created)
    expect(GeofenceEvent.last.source).to eq('native_app')
  end

  it 'returns 204 when area does not belong to user' do
    other_area = create(:area)
    post '/api/v1/points/transitions', params: payload(area_id: other_area.id), headers: headers
    expect(response).to have_http_status(:no_content)
  end

  it 'rejects occurred_at more than 5 minutes in the future' do
    post '/api/v1/points/transitions', params: payload(occurred_at: 10.minutes.from_now.iso8601), headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'accepts offline-queued occurred_at up to 24h in the past' do
    post '/api/v1/points/transitions', params: payload(occurred_at: 12.hours.ago.iso8601), headers: headers
    expect(response).to have_http_status(:created)
  end

  it 'rejects occurred_at more than 24h in the past' do
    post '/api/v1/points/transitions', params: payload(occurred_at: 26.hours.ago.iso8601), headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects when write API is disabled (Lite user on cloud)' do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    lite_user = create(:user, plan: :lite)
    lite_headers = { 'Authorization' => "Bearer #{lite_user.api_key}", 'CONTENT_TYPE' => 'application/json' }
    post '/api/v1/points/transitions', params: payload(area_id: create(:area, user: lite_user).id), headers: lite_headers
    expect(response).to have_http_status(:forbidden)
  end

  it 'rejects invalid event_type' do
    post '/api/v1/points/transitions', params: payload(event_type: 'arrive'), headers: headers
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'requires authentication' do
    post '/api/v1/points/transitions', params: payload
    expect(response).to have_http_status(:unauthorized)
  end
end
