# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::GeofenceEvents', type: :request do
  let(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:home) { create(:area, user:, name: 'Home') }
  let(:work) { create(:area, user:, name: 'Work') }

  def json
    JSON.parse(response.body)
  end

  it 'lists real events newest first, filtered by area' do
    older = create(:geofence_event, user:, area: home, occurred_at: 2.hours.ago)
    newer = create(:geofence_event, user:, area: home, event_type: :leave, occurred_at: 1.hour.ago)
    create(:geofence_event, user:, area: work)
    create(:geofence_event, user:, area: home, synthetic: true)

    get '/api/v1/geofence_events', params: { area_id: home.id }, headers: headers

    expect(json.map { |e| e['id'] }).to eq([newer.id, older.id])
    expect(json.first).to include('area_name' => 'Home', 'event_type' => 'leave', 'source' => 'native_app')
  end

  it 'reads the date range in the user\'s timezone' do
    inside = create(:geofence_event, user:, area: home, occurred_at: Time.utc(2026, 10, 23, 22, 30))
    create(:geofence_event, user:, area: home, occurred_at: Time.utc(2026, 10, 23, 21, 30))

    get '/api/v1/geofence_events', params: { start_at: '2026-10-24', end_at: '2026-10-24' }, headers: headers

    expect(json.map { |e| e['id'] }).to eq([inside.id])
  end

  it 'never lists another user\'s events' do
    create(:geofence_event)

    get '/api/v1/geofence_events', headers: headers

    expect(json).to be_empty
  end
end
