# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Tiles::Anomalies', type: :request do
  let(:user) { create(:user) }
  # z10, point-attribute regime — accuracy only exists at z >= 5
  let(:path) { '/api/v1/tiles/anomalies/10/512/511.mvt' }

  describe 'GET /show' do
    it 'serves only anomalous points, with the accuracy property for popup reasons' do
      create(:point, user:, longitude: 0.01, latitude: 0.01, lonlat: 'POINT(0.01 0.01)',
                     anomaly: true, accuracy: 12_000)

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
      expect(response.body.b).to include('accuracy')
    end

    it 'returns no content when the user has only ordinary points' do
      create(:point, user:, longitude: 0.01, latitude: 0.01, lonlat: 'POINT(0.01 0.01)')

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    it 'never serves another user\'s anomalies' do
      other = create(:user)
      create(:point, user: other, longitude: 0.01, latitude: 0.01, lonlat: 'POINT(0.01 0.01)', anomaly: true)

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    describe 'caching lifecycle' do
      let(:range) { { start_at: '2024-01-01T00:00:00Z', end_at: '2024-12-31T23:59:59Z' } }

      it 'caches like points tiles and invalidates when the points epoch bumps' do
        create(:point, user:, longitude: 0.01, latitude: 0.01, lonlat: 'POINT(0.01 0.01)',
                       anomaly: true, timestamp: Time.utc(2024, 6, 1).to_i)

        get path, params: range.merge(api_key: user.api_key)
        expect(response).to have_http_status(:ok)
        expect(response.headers['Cache-Control']).to include('max-age=300', 'private')
        etag = response.headers['ETag']
        expect(etag).to be_present

        get path, params: range.merge(api_key: user.api_key), headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:not_modified)

        # The anomalies endpoint rides the POINTS epoch — an anomaly flip bumps it.
        Points::TileEpoch.bump(user.id, timestamps: [Time.utc(2024, 6, 1).to_i])

        get path, params: range.merge(api_key: user.api_key), headers: { 'If-None-Match' => etag }
        expect(response).to have_http_status(:ok)
      end

      it 'rejects a reversed range with 400 and no-store' do
        get path, params: { api_key: user.api_key,
                            start_at: '2024-12-31T00:00:00Z', end_at: '2024-01-01T00:00:00Z' }

        expect(response).to have_http_status(:bad_request)
        expect(response.headers['Cache-Control']).to include('no-store')
      end
    end

    it 'returns 400 for invalid tile coordinates' do
      get '/api/v1/tiles/anomalies/2/9/0.mvt', params: { api_key: user.api_key }

      expect(response).to have_http_status(:bad_request)
    end

    it 'rejects unauthenticated requests' do
      get path

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
