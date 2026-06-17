# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Flights', type: :request do
  let(:user) { create(:user) }

  it 'returns the user flights as a FeatureCollection' do
    create(:flight, user: user)
    create(:flight)

    get '/api/v1/flights', params: { api_key: user.api_key }

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body['type']).to eq('FeatureCollection')
    expect(body['features'].size).to eq(1)
  end

  it 'rejects unauthenticated requests' do
    get '/api/v1/flights'
    expect(response).to have_http_status(:unauthorized)
  end

  it 'filters by departure_time range' do
    create(:flight, user: user, departure_time: Time.utc(2026, 1, 1, 10))
    create(:flight, user: user, departure_time: Time.utc(2026, 6, 1, 10))

    get '/api/v1/flights', params: { api_key: user.api_key, start_at: '2026-05-01', end_at: '2026-07-01' }

    expect(response.parsed_body['features'].size).to eq(1)
  end

  it 'falls back to default range on unparseable date params' do
    create(:flight, user: user, departure_time: Time.utc(2026, 1, 1, 10))

    get '/api/v1/flights', params: { api_key: user.api_key, start_at: '25:99:99', end_at: 'garbage' }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['features'].size).to eq(1)
  end

  it 'excludes flights without airport coordinates' do
    create(:flight, user: user)
    create(:flight, user: user, from_lat: nil, from_lon: nil)
    create(:flight, user: user, to_lat: nil)

    get '/api/v1/flights', params: { api_key: user.api_key }

    expect(response.parsed_body['features'].size).to eq(1)
  end

  it 'caps the number of returned flights' do
    stub_const('Api::V1::FlightsController::MAX_FLIGHTS', 2)
    create_list(:flight, 3, user: user)

    get '/api/v1/flights', params: { api_key: user.api_key }

    expect(response.parsed_body['features'].size).to eq(2)
  end
end
