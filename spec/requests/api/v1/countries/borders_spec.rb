# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Countries::Borders', type: :request do
  describe 'GET /index' do
    context 'when user is not authenticated' do
      it 'returns http unauthorized' do
        get '/api/v1/countries/borders'

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns X-Dawarich-Response header' do
        get '/api/v1/countries/borders'

        expect(response.headers['X-Dawarich-Response']).to eq('Hey, I\'m alive!')
        expect(response.headers['X-Dawarich-Version']).to eq(APP_VERSION)
      end
    end

    context 'when user is authenticated' do
      let(:user) { create(:user) }

      it 'returns a list of countries with borders' do
        get '/api/v1/countries/borders', headers: { 'Authorization' => "Bearer #{user.api_key}" }

        expect(response).to have_http_status(:success)
        expect(response.body).to include('AF')
        expect(response.body).to include('ZW')
      end

      it 'returns X-Dawarich-Response header' do
        get '/api/v1/countries/borders', headers: { 'Authorization' => "Bearer #{user.api_key}" }

        expect(response.headers['X-Dawarich-Response']).to eq('Hey, I\'m alive and authenticated!')
        expect(response.headers['X-Dawarich-Version']).to eq(APP_VERSION)
      end
    end
  end
end
