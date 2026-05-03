# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/login', type: :request do
  let!(:user) { create(:user, email: 'me@example.com', password: 'secret123456') }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    # The login throttle is cloud-only — self-hosted instances skip it.
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  after { Rack::Attack.enabled = false }

  it 'returns 200 with api_key on correct credentials' do
    post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['api_key']).to eq(user.api_key)
    expect(body['user_id']).to eq(user.id)
    expect(body).not_to have_key('two_factor_required')
  end

  it 'returns 401 on wrong password' do
    post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'wrong' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 on unknown email' do
    post '/api/v1/auth/login', params: { email: 'nope@example.com', password: 'secret123456' }
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'shared API middleware' do
    # BaseController inherits from ApiController, so the version header and
    # rate-limit header pipeline are applied consistently across all API
    # endpoints. These are served by ApplicationController-level hooks
    # (set_version_header, set_rate_limit_headers) that would otherwise be
    # absent if BaseController inherited from ActionController::API directly.
    it 'sends the X-Dawarich-Version header from ApiController' do
      post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
      expect(response.headers['X-Dawarich-Version']).to be_present
      expect(response.headers['X-Dawarich-Response']).to be_present
    end
  end

  describe 'timing-attack resistance' do
    it 'runs a bcrypt comparison on the unknown-email path (constant time)' do
      # Observable behavior: a bcrypt password verification happens even when
      # no user exists for the submitted email. We assert this by watching
      # BCrypt::Password#is_password? — it is the heavy operation that, if
      # skipped, reveals account existence through response timing.
      expect(BCrypt::Password).to receive(:new).and_call_original.at_least(:once)
      post '/api/v1/auth/login', params: { email: 'no-such-user@example.com', password: 'whatever' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'includes current plan/status/subscription_source on success' do
    user.update!(status: :active, plan: :pro, subscription_source: :paddle, active_until: 1.year.from_now)
    post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
    body = JSON.parse(response.body)
    expect(body['plan']).to eq('pro')
    expect(body['status']).to eq('active')
    expect(body['subscription_source']).to eq('paddle')
  end

  context 'user has 2FA enabled' do
    before do
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'returns 202 with a challenge_token and no api_key' do
      post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body['two_factor_required']).to be true
      expect(body['challenge_token']).to be_present
      expect(body['ttl']).to eq(300)
      expect(body).not_to have_key('api_key')
    end

    it 'still returns 401 on wrong password (does not reveal 2FA state)' do
      post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'wrong' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'DawarichSettings.two_factor_available? is false' do
    before do
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(false)
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'logs the user in normally, ignoring the otp flag' do
      post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'brute-force protection' do
    it 'throttles repeated attempts against the same email to 5 per minute' do
      5.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }
        expect(response).to have_http_status(:unauthorized)
      end
      post '/api/v1/auth/login',
           params: { email: 'me@example.com', password: 'wrong' }
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'normalises email casing/whitespace so case variations share the same bucket' do
      5.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }
      end
      post '/api/v1/auth/login',
           params: { email: '  ME@Example.com  ', password: 'wrong' }
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'throttles repeated attempts from the same IP across many emails to 20 per minute' do
      # 20 attempts from this IP, each with a different email so the email throttle
      # does not fire (each email still under the per-email limit of 5).
      20.times do |i|
        post '/api/v1/auth/login',
             params: { email: "user#{i}@example.com", password: 'wrong' }
      end
      post '/api/v1/auth/login',
           params: { email: 'user-final@example.com', password: 'wrong' }
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'returns the shared rate-limit error envelope when throttled' do
      6.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }
      end
      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('rate_limit_exceeded')
      expect(response.headers['Retry-After']).to be_present
    end

    it 'still permits a successful login while under the limit' do
      4.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }
      end
      post '/api/v1/auth/login',
           params: { email: 'me@example.com', password: 'secret123456' }
      expect(response).to have_http_status(:ok)
    end
  end
end
