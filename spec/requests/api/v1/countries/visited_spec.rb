# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Countries::Visited', type: :request do
  let(:user) { create(:user) }

  it 'returns country metadata without point data' do
    country = create(:country, name: 'Germany', iso_a2: 'DE', iso_a3: 'DEU')
    create(:point, user:, country:, timestamp: 1_000)

    get '/api/v1/countries/visited', params: { api_key: user.api_key, start_at: 900, end_at: 1_200 }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('countries' => [{ 'iso_a3' => 'DEU', 'name' => 'Germany' }])
  end

  it 'requires a strict history scope' do
    get '/api/v1/countries/visited', params: { api_key: user.api_key, start_at: 'bad', end_at: 1_200 }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'rejects reversed and incomplete history scopes' do
    [
      { start_at: 1_200, end_at: 900 },
      { start_at: 900 },
      { end_at: 1_200 }
    ].each do |history_scope|
      get '/api/v1/countries/visited', params: history_scope.merge(api_key: user.api_key)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'normalizes equivalent ISO-8601 and epoch scopes to the same ETag' do
    get '/api/v1/countries/visited', params: { api_key: user.api_key, start_at: 900, end_at: 1_200 }
    epoch_etag = response.headers.fetch('ETag')

    get '/api/v1/countries/visited', params: {
      api_key: user.api_key,
      start_at: Time.zone.at(900).iso8601,
      end_at: Time.zone.at(1_200).iso8601
    }

    expect(response.headers.fetch('ETag')).to eq(epoch_etag)
  end

  it 'accepts the minute-precision ISO-8601 scope emitted by the map' do
    start_at = Time.zone.at(900).strftime('%Y-%m-%dT%H:%M%:z')
    end_at = Time.zone.at(1_200).strftime('%Y-%m-%dT%H:%M%:z')

    get '/api/v1/countries/visited', params: { api_key: user.api_key, start_at: start_at, end_at: end_at }

    expect(response).to have_http_status(:ok)
  end

  it 'returns a private 304 without repeating the metadata query' do
    allow(Countries::VisitedQuery).to receive(:new).and_call_original

    get '/api/v1/countries/visited', params: { api_key: user.api_key, start_at: 900, end_at: 1_200 }
    etag = response.headers.fetch('ETag')
    expect(response.headers['Cache-Control']).to include('private')

    get '/api/v1/countries/visited',
        params: { api_key: user.api_key, start_at: 900, end_at: 1_200 },
        headers: { 'If-None-Match' => etag }

    expect(response).to have_http_status(:not_modified)
    expect(Countries::VisitedQuery).to have_received(:new).once
  end
end
