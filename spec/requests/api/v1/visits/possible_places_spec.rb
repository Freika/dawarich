# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/visits/:id/possible_places' do
  let(:user) { create(:user) }
  let(:visit) { create(:visit, user: user, area: nil, place: place) }
  let(:place) { create(:place, user: user, name: 'Current Place', latitude: 52.5126, longitude: 13.4012) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    Rails.cache.clear
  end

  let(:photon_hashes) do
    [{
      id: nil, name: 'Café Bravo', latitude: 52.5126, longitude: 13.4012,
      osm_id: 1_234_567, source: 'photon', geodata: { 'properties' => { 'osm_id' => 1_234_567 } }
    }]
  end

  it 'returns 404 for a tombstoned visit' do
    tombstone = create(:visit, user: user, area: nil, place: nil, deleted_at: 1.day.ago)

    get "/api/v1/visits/#{tombstone.id}/possible_places", headers: headers

    expect(response).to have_http_status(:not_found)
  end

  it 'returns Photon hashes prepended with the current place' do
    allow_any_instance_of(Places::NearbySearch).to receive(:call).and_return(photon_hashes)

    get "/api/v1/visits/#{visit.id}/possible_places", headers: headers

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.first['id']).to eq(place.id)
    expect(body.first['name']).to eq('Current Place')
    expect(body.last['id']).to be_nil
    expect(body.last['name']).to eq('Café Bravo')
  end

  it 'deduplicates the current place by osm_id when Photon also returns it' do
    place.update!(geodata: { 'properties' => { 'osm_id' => 1_234_567 } })
    allow_any_instance_of(Places::NearbySearch).to receive(:call).and_return(photon_hashes)

    get "/api/v1/visits/#{visit.id}/possible_places", headers: headers

    body = JSON.parse(response.body)
    expect(body.count { |p| p['osm_id'] == 1_234_567 }).to eq(1)
    expect(body.first['id']).to eq(place.id)
  end

  it 'prepends a manual current place (no osm_id) without false-positive dedup' do
    allow_any_instance_of(Places::NearbySearch).to receive(:call).and_return(photon_hashes)

    get "/api/v1/visits/#{visit.id}/possible_places", headers: headers

    body = JSON.parse(response.body)
    expect(body.first['id']).to eq(place.id)
    expect(body.first['osm_id']).to be_nil
    expect(body.size).to eq(2)
  end

  it 'returns 404 when visit not found' do
    get '/api/v1/visits/999999999/possible_places', headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it 'does NOT create any DB rows during the request' do
    allow_any_instance_of(Places::NearbySearch).to receive(:call).and_return(photon_hashes)
    visit_id = visit.id
    expect { get "/api/v1/visits/#{visit_id}/possible_places", headers: headers }
      .not_to(change { Place.count })
  end
end
