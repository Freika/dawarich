# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Immich::Enrich', type: :request do
  let(:user) do
    create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
  end

  let(:empty_page_body) do
    { 'assets' => { 'total' => 0, 'count' => 0, 'items' => [] } }.to_json
  end

  describe 'POST /api/v1/immich/enrich/scan' do
    let(:scan_params) do
      { start_date: '2024-01-15', end_date: '2024-01-16', tolerance: 1800 }
    end

    let(:immich_response_body) do
      {
        'assets' => {
          'total' => 1, 'count' => 1,
          'items' => [
            {
              'id' => 'asset-1',
              'originalFileName' => 'IMG_001.jpg',
              'localDateTime' => '2024-01-15T10:23:00.000Z',
              'exifInfo' => {
                'dateTimeOriginal' => '2024-01-15T10:23:00.000Z',
                'latitude' => nil, 'longitude' => nil
              }
            }
          ]
        }
      }.to_json
    end

    before do
      stub_request(:post, 'http://immich.app/api/search/metadata')
        .to_return(
          { status: 200, body: immich_response_body, headers: { 'content-type' => 'application/json' } },
          { status: 200, body: empty_page_body, headers: { 'content-type' => 'application/json' } }
        )
    end

    context 'when authenticated' do
      let!(:point) do
        create(:point, user:,
               latitude: 52.52, longitude: 13.405,
               lonlat: 'POINT(13.405 52.52)',
               timestamp: Time.utc(2024, 1, 15, 10, 25).to_i)
      end

      it 'returns scan results' do
        post '/api/v1/immich/enrich/scan', params: scan_params.merge(api_key: user.api_key)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['total_without_geodata']).to eq(1)
        expect(body['total_matched']).to eq(1)
        expect(body['matches'].first['immich_asset_id']).to eq('asset-1')
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        post '/api/v1/immich/enrich/scan', params: scan_params

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/immich/enrich' do
    let(:enrich_params) do
      {
        assets: [
          { immich_asset_id: 'uuid-1', latitude: 52.52, longitude: 13.405 }
        ]
      }
    end

    before do
      stub_request(:put, 'http://immich.app/api/assets/uuid-1')
        .to_return(status: 200, body: '{}', headers: { 'content-type' => 'application/json' })
    end

    context 'when authenticated' do
      it 'enriches photos and returns results' do
        post '/api/v1/immich/enrich',
             params: enrich_params.merge(api_key: user.api_key),
             as: :json

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body['enriched']).to eq(1)
        expect(body['failed']).to eq(0)
      end
    end

    context 'when not authenticated' do
      it 'returns unauthorized' do
        post '/api/v1/immich/enrich', params: enrich_params, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
