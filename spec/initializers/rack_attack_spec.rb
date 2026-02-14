# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Rack::Attack', type: :request do
  let(:user) { create(:user) }

  before do
    # Use memory store for tests to avoid Redis dependency
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  after do
    Rack::Attack.reset!
  end

  describe 'safelists' do
    it 'allows localhost requests without throttling' do
      70.times do
        get '/api/v1/health'
      end

      expect(response).to have_http_status(:success)
    end
  end

  describe 'public/health throttle' do
    it 'throttles health endpoint after 60 requests per minute' do
      61.times do
        get '/api/v1/health', headers: { 'REMOTE_ADDR' => '1.2.3.4' }
      end

      expect(response).to have_http_status(:too_many_requests)

      body = JSON.parse(response.body)
      expect(body['error']).to eq('Rate limit exceeded')
      expect(body['retry_after']).to be_a(Integer)
      expect(response.headers['Retry-After']).to be_present
      expect(response.headers['X-RateLimit-Limit']).to eq('60')
      expect(response.headers['X-RateLimit-Remaining']).to eq('0')
    end
  end

  describe 'public/login throttle' do
    it 'throttles login after 10 attempts per minute' do
      11.times do
        post '/users/sign_in',
             params: { user: { email: 'test@example.com', password: 'wrong' } },
             headers: { 'REMOTE_ADDR' => '2.3.4.5' }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'public/subscription_callback throttle' do
    it 'throttles subscription callback after 10 requests per minute' do
      11.times do
        post '/api/v1/subscriptions/callback',
             params: { api_key: user.api_key },
             headers: { 'REMOTE_ADDR' => '3.4.5.6' }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'api/location_ingestion throttle' do
    it 'throttles overland batches after 60 requests per minute' do
      61.times do
        post '/api/v1/overland/batches',
             params: { api_key: user.api_key },
             headers: { 'REMOTE_ADDR' => '4.5.6.7' }
      end

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'throttles owntracks points after 60 requests per minute' do
      61.times do
        post '/api/v1/owntracks/points',
             params: { api_key: user.api_key },
             headers: { 'REMOTE_ADDR' => '5.6.7.8' }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'api/destructive_ops throttle' do
    it 'throttles bulk_destroy after 10 requests per minute' do
      11.times do
        delete '/api/v1/points/bulk_destroy',
               params: { api_key: user.api_key },
               headers: { 'REMOTE_ADDR' => '6.7.8.9' }
      end

      expect(response).to have_http_status(:too_many_requests)
    end

    it 'throttles settings update after 10 requests per minute' do
      11.times do
        patch '/api/v1/settings',
              params: { api_key: user.api_key },
              headers: { 'REMOTE_ADDR' => '7.8.9.10' }
      end

      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe 'api/general throttle' do
    it 'allows up to 600 requests per minute for authenticated API calls' do
      # Verify requests within limit succeed
      get '/api/v1/health',
          headers: {
            'Authorization' => "Bearer #{user.api_key}",
            'REMOTE_ADDR' => '8.9.10.11'
          }

      expect(response).to have_http_status(:success)
    end
  end

  describe '429 response format' do
    it 'returns JSON with error details and rate limit headers' do
      11.times do
        post '/users/sign_in',
             params: { user: { email: 'test@example.com', password: 'wrong' } },
             headers: { 'REMOTE_ADDR' => '9.10.11.12' }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.content_type).to include('application/json')

      body = JSON.parse(response.body)
      expect(body).to have_key('error')
      expect(body).to have_key('retry_after')
      expect(response.headers).to have_key('Retry-After')
      expect(response.headers).to have_key('X-RateLimit-Limit')
      expect(response.headers).to have_key('X-RateLimit-Remaining')
      expect(response.headers).to have_key('X-RateLimit-Reset')
    end
  end
end
