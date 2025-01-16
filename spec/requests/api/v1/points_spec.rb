# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Points', type: :request do
  let!(:user) { create(:user) }
  let!(:points) { create_list(:point, 15, user:) }

  describe 'GET /index' do
    context 'when regular version of points is requested' do
      it 'renders a successful response' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response).to be_successful
      end

      it 'returns a list of points' do
        get api_v1_points_url(api_key: user.api_key)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(15)
      end

      it 'returns a list of points with pagination' do
        get api_v1_points_url(api_key: user.api_key, page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(5)
      end

      it 'returns a list of points with pagination headers' do
        get api_v1_points_url(api_key: user.api_key, page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        expect(response.headers['X-Current-Page']).to eq('2')
        expect(response.headers['X-Total-Pages']).to eq('2')
      end
    end

    context 'when slim version of points is requested' do
      it 'renders a successful response' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true')

        expect(response).to be_successful
      end

      it 'returns a list of points' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(15)
      end

      it 'returns a list of points with pagination' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true', page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(5)
      end

      it 'returns a list of points with pagination headers' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true', page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        expect(response.headers['X-Current-Page']).to eq('2')
        expect(response.headers['X-Total-Pages']).to eq('2')
      end

      it 'returns a list of points with slim attributes' do
        get api_v1_points_url(api_key: user.api_key, slim: 'true')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        json_response.each do |point|
          expect(point.keys).to eq(%w[id latitude longitude timestamp])
        end
      end
    end

    context 'when order param is provided' do
      it 'returns points in ascending order' do
        get api_v1_points_url(api_key: user.api_key, order: 'asc')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.first['timestamp']).to be < json_response.last['timestamp']
      end

      it 'returns points in descending order' do
        get api_v1_points_url(api_key: user.api_key, order: 'desc')

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.first['timestamp']).to be > json_response.last['timestamp']
      end
    end
  end

  describe 'PATCH /update' do
    let!(:point) { create(:point, latitude: 1.0, longitude: 1.0, user:) }

    it 'updates a point' do
      patch "/api/v1/points/#{point.id}?api_key=#{user.api_key}",
            params: { point: { latitude: 1.1, longitude: 1.1 } }

      expect(response).to have_http_status(:ok)

      expect(point.reload.latitude).to eq(1.1)
      expect(point.reload.longitude).to eq(1.1)
    end
  end
end
