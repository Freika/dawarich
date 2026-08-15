# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/visits ignores cross-tenant place_id', type: :request do
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:foreign_place) do
    create(:place, user: other_user, name: 'Foreign secret', latitude: 48.8566, longitude: 2.3522)
  end
  let(:auth_headers) do
    { 'Authorization' => "Bearer #{owner.api_key}", 'Content-Type' => 'application/json' }
  end
  let(:create_params) do
    {
      visit: {
        name: 'Probe',
        latitude: 52.5200,
        longitude: 13.4050,
        started_at: '2026-01-01T10:00:00Z',
        ended_at: '2026-01-01T11:00:00Z',
        place_id: foreign_place.id
      }
    }
  end

  it 'does not link the new visit to a foreign place_id' do
    post '/api/v1/visits', params: create_params.to_json, headers: auth_headers

    expect(response).to have_http_status(:ok)
    visit = owner.visits.last
    expect(visit.place_id).not_to eq(foreign_place.id)
    expect(visit.place.user_id).to eq(owner.id)
  end

  it 'does not echo the foreign place coordinates in the create response' do
    post '/api/v1/visits', params: create_params.to_json, headers: auth_headers

    body = JSON.parse(response.body)
    expect(body.dig('place', 'latitude')).not_to eq(foreign_place.latitude)
    expect(body.dig('place', 'longitude')).not_to eq(foreign_place.longitude)
    expect(body.dig('place', 'id')).not_to eq(foreign_place.id)
  end

  it 'creates the visit at the requested coordinates with a user-owned place' do
    expect { post '/api/v1/visits', params: create_params.to_json, headers: auth_headers }
      .to change { owner.visits.count }.by(1)

    visit = owner.visits.last
    expect(visit.place.latitude).to eq(52.5200)
    expect(visit.place.longitude).to eq(13.4050)
    expect(visit.place.user_id).to eq(owner.id)
  end
end
