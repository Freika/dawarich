# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Points', type: :request do
  let!(:user) { create(:user) }
  let!(:points) { create_list(:point, 150, user:) }

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

        expect(json_response.size).to eq(100)
      end

      it 'returns a list of points with pagination' do
        get api_v1_points_url(api_key: user.api_key, page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(10)
      end

      it 'returns a list of points with pagination headers' do
        get api_v1_points_url(api_key: user.api_key, page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        expect(response.headers['X-Current-Page']).to eq('2')
        expect(response.headers['X-Total-Pages']).to eq('15')
      end
    end

    context 'when slim version of points is requested' do
      it 'renders a successful response' do
        get api_v1_points_url(api_key: user.api_key, slim: true)

        expect(response).to be_successful
      end

      it 'returns a list of points' do
        get api_v1_points_url(api_key: user.api_key, slim: true)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(100)
      end

      it 'returns a list of points with pagination' do
        get api_v1_points_url(api_key: user.api_key, slim: true, page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        expect(json_response.size).to eq(10)
      end

      it 'returns a list of points with pagination headers' do
        get api_v1_points_url(api_key: user.api_key, slim: true, page: 2, per_page: 10)

        expect(response).to have_http_status(:ok)

        expect(response.headers['X-Current-Page']).to eq('2')
        expect(response.headers['X-Total-Pages']).to eq('15')
      end

      it 'returns a list of points with slim attributes' do
        get api_v1_points_url(api_key: user.api_key, slim: true)

        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)

        json_response.each do |point|
          expect(point.keys).to eq(%w[latitude longitude timestamp])
        end
      end
    end
  end
end
