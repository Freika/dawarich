# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Existing places in visit search', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:latitude) { 52.437 }
  let(:longitude) { 13.539 }

  before do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
    allow(Geocoder).to receive(:search).and_return([])
  end

  it 'finds and assigns a saved place by name' do
    place = create(
      :place,
      user: user,
      name: 'Home',
      source: :manual,
      latitude: latitude + 0.1,
      longitude: longitude + 0.1
    )
    visit = create(:visit, user: user)

    get '/api/v1/places/search',
        params: { q: 'Home', lat: latitude, lon: longitude, radius: 1.0 },
        headers: headers

    result = JSON.parse(response.body).fetch('places').find { |candidate| candidate['id'] == place.id }
    expect(result).to include('name' => 'Home', 'source' => 'manual')

    patch "/api/v1/visits/#{visit.id}", params: { visit: { place_id: result['id'] } }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(visit.reload.place).to eq(place)
  end

  it 'returns nearby saved places without a query when reverse geocoding is disabled' do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)
    place = create(
      :place,
      user: user,
      name: 'Local Place',
      source: :manual,
      latitude: latitude,
      longitude: longitude
    )

    get '/api/v1/places/search', params: { lat: latitude, lon: longitude }, headers: headers

    expect(JSON.parse(response.body).fetch('places')).to include(include('id' => place.id, 'name' => 'Local Place'))
  end

  it 'preserves separate geocoder results that share a name' do
    results = [
      { id: nil, name: 'Coffee Shop', latitude: latitude, longitude: longitude, source: 'photon' },
      { id: nil, name: 'Coffee Shop', latitude: latitude + 0.001, longitude: longitude, source: 'photon' }
    ]
    search = instance_double(Places::Search, call: results)
    allow(Places::Search).to receive(:new).and_return(search)

    get '/api/v1/places/search',
        params: { q: 'Coffee', lat: latitude, lon: longitude },
        headers: headers

    expect(JSON.parse(response.body).fetch('places').count { |place| place['name'] == 'Coffee Shop' }).to eq(2)
  end

  it 'does not expose another users saved places' do
    other_place = create(
      :place,
      user: create(:user),
      name: 'Private Home',
      source: :manual,
      latitude: latitude,
      longitude: longitude
    )

    get '/api/v1/places/search',
        params: { q: 'Private Home', lat: latitude, lon: longitude },
        headers: headers

    expect(JSON.parse(response.body).fetch('places').pluck('id')).not_to include(other_place.id)
  end
end
