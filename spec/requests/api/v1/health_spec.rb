# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Healths', type: :request do
  describe 'GET /index' do
    context 'when user is not authenticated' do
      it 'returns http success' do
        get '/api/v1/health'

        expect(response).to have_http_status(:success)
        expect(response.headers['X-Dawarich-Response']).to eq('Hey, I\'m alive!')
      end
    end

    context 'when user is authenticated' do
      let(:user) { create(:user) }

      it 'returns http success' do
        get '/api/v1/health', headers: { 'Authorization' => "Bearer #{user.api_key}" }

        expect(response).to have_http_status(:success)
        expect(response.headers['X-Dawarich-Response']).to eq('Hey, I\'m alive and authenticated!')
      end
    end

    it 'returns the correct version' do
      get '/api/v1/health'

      expect(response.headers['X-Dawarich-Version']).to eq(APP_VERSION)
    end
  end
end
