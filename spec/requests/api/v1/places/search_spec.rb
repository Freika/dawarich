# frozen_string_literal: true

require 'rails_helper'
require 'geocoder/results/photon'

RSpec.describe 'Api::V1::Places::Search', type: :request do
  let(:user) { create(:user) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:lat) { 52.437 }
  let(:lon) { 13.539 }

  before { allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true) }

  def photon(name:, plat:, plon:)
    instance_double(
      Geocoder::Result::Photon,
      data: {
        'properties' => { 'name' => name, 'osm_id' => name.hash.abs },
        'geometry' => { 'coordinates' => [plon, plat], 'type' => 'Point' }
      }
    )
  end

  it 'returns 400 when coordinates are missing' do
    get '/api/v1/places/search', params: { q: 'cafe' }, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it 'returns 400 for out-of-range coordinates' do
    get '/api/v1/places/search', params: { lat: 200, lon: 13.5 }, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it 'with a query, returns forward matches within radius and merges nearby areas' do
    create(:area, user: user, name: 'Home', latitude: lat, longitude: lon, radius: 100)
    near = photon(name: 'Café Bravo', plat: lat, plon: lon)
    far  = photon(name: 'Far Café', plat: 53.5, plon: 14.5)
    allow(Geocoder).to receive(:search).and_return([near, far])

    get '/api/v1/places/search', params: { q: 'caf', lat: lat, lon: lon, radius: 1.0 }, headers: headers

    expect(response).to have_http_status(:success)
    json = JSON.parse(response.body)
    expect(json['places'].map { |p| p['name'] }).to eq(['Café Bravo'])
    expect(json['areas'].map { |a| a['name'] }).to eq(['Home'])
  end

  it 'with a blank query, returns nearby reverse suggestions' do
    allow(Geocoder).to receive(:search).and_return([photon(name: 'Nearby Spot', plat: lat, plon: lon)])

    get '/api/v1/places/search', params: { lat: lat, lon: lon }, headers: headers

    expect(response).to have_http_status(:success)
    json = JSON.parse(response.body)
    expect(json['places'].map { |p| p['name'] }).to include('Nearby Spot')
  end

  it 'returns empty places (not an error) when reverse geocoding is disabled' do
    allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

    get '/api/v1/places/search', params: { q: 'cafe', lat: lat, lon: lon }, headers: headers

    expect(response).to have_http_status(:success)
    expect(JSON.parse(response.body)['places']).to eq([])
  end
end
