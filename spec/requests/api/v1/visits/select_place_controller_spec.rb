# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/visits/:id/select_place' do
  let(:user)  { create(:user) }
  let(:other) { create(:user) }
  let(:visit) { create(:visit, user: user, area: nil, place: nil) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before { allow(DawarichSettings).to receive(:store_geodata?).and_return(true) }

  let(:photon_payload) do
    {
      photon: {
        name: 'Café Bravo',
        latitude: 52.5126,
        longitude: 13.4012,
        osm_id: 1_234_567,
        city: 'Berlin',
        country: 'Germany',
        geodata: { 'properties' => { 'osm_id' => 1_234_567 } }
      }
    }
  end

  it 'excludes tombstoned visits from the serialized visits_count' do
    existing_place = create(:place, user: user, name: 'Café Bravo', latitude: 52.5126, longitude: 13.4012)
    create(:visit, user: user, place: existing_place, area: nil, deleted_at: 1.day.ago)

    post "/api/v1/visits/#{visit.id}/select_place", params: photon_payload, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body['id']).to eq(existing_place.id)
    expect(body['visits_count']).to eq(1)
  end

  it 'returns 404 for a tombstoned visit' do
    tombstone = create(:visit, user: user, area: nil, place: nil, deleted_at: 1.day.ago)

    post "/api/v1/visits/#{tombstone.id}/select_place", params: photon_payload, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(tombstone.reload.place_id).to be_nil
  end

  it 'creates a place and assigns it to the visit (201)' do
    post "/api/v1/visits/#{visit.id}/select_place", params: photon_payload, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body['name']).to eq('Café Bravo')
    expect(body['id']).to eq(visit.reload.place_id)
  end

  it 'returns 404 for a visit not owned by current user' do
    other_visit = create(:visit, user: other, area: nil)
    post "/api/v1/visits/#{other_visit.id}/select_place", params: photon_payload, headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'returns 422 when name is missing' do
    payload = photon_payload.deep_dup
    payload[:photon].delete(:name)
    post "/api/v1/visits/#{visit.id}/select_place", params: payload, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end
end
