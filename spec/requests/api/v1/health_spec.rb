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

  describe 'GET /ready' do
    let(:probe_headers) { { 'Host' => 'staging.dawarich.app', 'X-Forwarded-Proto' => 'https' } }

    it 'returns success when PostgreSQL and Redis respond' do
      allow(ActiveRecord::Base.connection).to receive(:select_value).with('SELECT 1').and_return(1)
      allow(Sidekiq).to receive(:redis).and_yield(double(call: 'PONG'))

      get '/api/v1/ready', headers: probe_headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('status' => 'ok')
    end

    it 'returns unavailable when PostgreSQL fails' do
      allow(ActiveRecord::Base.connection).to receive(:select_value).with('SELECT 1').and_raise(PG::ConnectionBad)

      get '/api/v1/ready', headers: probe_headers

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('status' => 'unavailable')
    end

    it 'returns unavailable when Redis fails' do
      allow(ActiveRecord::Base.connection).to receive(:select_value).with('SELECT 1').and_return(1)
      allow(Sidekiq).to receive(:redis).and_raise(RedisClient::CannotConnectError)

      get '/api/v1/ready', headers: probe_headers

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body).to eq('status' => 'unavailable')
    end
  end
end
