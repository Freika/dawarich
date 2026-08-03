# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Tiles::Points', type: :request do
  let(:user) { create(:user) }
  let(:path) { '/api/v1/tiles/points/0/0/0.mvt' }

  describe 'GET /show' do
    it 'returns a vector tile for authenticated requests' do
      create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
      expect(response.body.bytesize).to be_positive
    end

    it 'names properties to match the map point popup contract' do
      create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, params: { api_key: user.api_key }

      # MVT keys are length-prefixed, so a bare 'id' would also match track_id
      body = response.body.b

      expect(body).to include("\x1a\x02id".b, 'timestamp', 'battery', 'altitude', 'velocity')
      expect(body).not_to include('point_id')
    end

    it 'accepts bearer authentication' do
      create(:point, user:, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/vnd.mapbox-vector-tile')
    end

    it 'returns 401 without authentication' do
      get path

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 204 when the tile has no points for the current user' do
      create(:point, longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    it 'applies date filtering' do
      create(:point, user:, timestamp: Time.zone.parse('2024-01-01').to_i,
                             longitude: 0.0, latitude: 0.0, lonlat: 'POINT(0 0)')

      get path, params: {
        api_key: user.api_key,
        start_at: Time.zone.parse('2024-02-01').to_i,
        end_at: Time.zone.parse('2024-02-28').to_i
      }

      expect(response).to have_http_status(:no_content)
    end

    it 'applies plan scoping for Lite users on Cloud' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update_column(:plan, User.plans[:lite])
      create(
        :point,
        user:,
        timestamp: (DawarichSettings::LITE_DATA_WINDOW + 1.day).ago.to_i,
        longitude: 0.0,
        latitude: 0.0,
        lonlat: 'POINT(0 0)'
      )

      get path, params: { api_key: user.api_key }

      expect(response).to have_http_status(:no_content)
    end

    it 'returns 400 for invalid tile coordinates' do
      get '/api/v1/tiles/points/1/5/0.mvt', params: { api_key: user.api_key }

      expect(response).to have_http_status(:bad_request)
      expect(JSON.parse(response.body)).to eq('error' => 'Invalid tile coordinates')
    end
  end
end
