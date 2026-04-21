# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/subscriptions/callback (RevenueCat)', type: :request do
  let(:user) { create(:user, status: :pending_payment) }

  before do
    Rails.cache.clear
    ENV['REVENUECAT_WEBHOOK_SECRET'] = 'revcat-secret'
    @_prior_manager_secret = ENV['SUBSCRIPTION_WEBHOOK_SECRET']
    ENV['SUBSCRIPTION_WEBHOOK_SECRET'] = 'manager-secret-for-spec'
  end

  after do
    ENV.delete('REVENUECAT_WEBHOOK_SECRET')
    if @_prior_manager_secret.nil?
      ENV.delete('SUBSCRIPTION_WEBHOOK_SECRET')
    else
      ENV['SUBSCRIPTION_WEBHOOK_SECRET'] = @_prior_manager_secret
    end
  end

  let(:payload) do
    {
      event: {
        id: SecureRandom.uuid,
        type: 'INITIAL_PURCHASE',
        app_user_id: user.id.to_s,
        product_id: 'dawarich.pro.yearly',
        expiration_at_ms: 7.days.from_now.to_i * 1000,
        event_timestamp_ms: Time.current.to_i * 1000,
        store: 'APP_STORE',
        period_type: 'TRIAL'
      }
    }
  end

  it 'updates user on valid RevenueCat webhook with raw secret' do
    post '/api/v1/subscriptions/callback',
         params: payload.to_json,
         headers: { 'Content-Type' => 'application/json', 'Authorization' => 'revcat-secret' }

    expect(response).to have_http_status(:ok)
    user.reload
    expect(user.status).to eq('trial')
    expect(user.subscription_source).to eq('apple_iap')
  end

  it 'accepts a Bearer-prefixed Authorization header' do
    post '/api/v1/subscriptions/callback',
         params: payload.to_json,
         headers: { 'Content-Type' => 'application/json', 'Authorization' => 'Bearer revcat-secret' }

    expect(response).to have_http_status(:ok)
    expect(user.reload.status).to eq('trial')
  end

  it 'returns 401 on wrong Authorization header' do
    post '/api/v1/subscriptions/callback',
         params: payload.to_json,
         headers: { 'Content-Type' => 'application/json', 'Authorization' => 'wrong-secret' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 when Authorization header is missing' do
    post '/api/v1/subscriptions/callback',
         params: payload.to_json,
         headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 503 if secret env not configured' do
    ENV.delete('REVENUECAT_WEBHOOK_SECRET')
    allow(Rails.application.credentials).to receive(:revenuecat).and_return(nil)
    post '/api/v1/subscriptions/callback',
         params: payload.to_json,
         headers: { 'Content-Type' => 'application/json', 'Authorization' => 'anything' }

    expect(response).to have_http_status(:service_unavailable)
  end

  it 'returns 503 with Retry-After header when user is unknown (forces RevenueCat to retry)' do
    bad_payload = payload.deep_dup
    bad_payload[:event][:app_user_id] = '99999999'

    post '/api/v1/subscriptions/callback',
         params: bad_payload.to_json,
         headers: { 'Content-Type' => 'application/json', 'Authorization' => 'revcat-secret' }

    expect(response).to have_http_status(:service_unavailable)
    expect(response.headers['Retry-After']).to eq('60')
  end

  describe 'Paddle manager callback path' do
    it 'returns 401 when token is invalid (not 500, not 503)' do
      post '/api/v1/subscriptions/callback',
           params: { token: 'obviously-bad-jwt' },
           headers: { 'X-Webhook-Secret' => 'manager-secret-for-spec' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'does not overwrite subscription_source when Paddle callback lands on an IAP user with future active_until' do
      iap_user = create(:user, subscription_source: :apple_iap, active_until: 1.year.from_now, status: :active)
      token_payload = {
        user_id: iap_user.id,
        status: 'active',
        active_until: 30.days.from_now.iso8601,
        plan: 'pro',
        exp: 30.minutes.from_now.to_i
      }
      secret_key = ENV['JWT_SECRET_KEY'] || 'test_secret'
      token = JWT.encode(token_payload, secret_key, 'HS256')

      post '/api/v1/subscriptions/callback',
           params: { token: token },
           headers: { 'X-Webhook-Secret' => 'manager-secret-for-spec' }

      expect(response).to have_http_status(:conflict)
      iap_user.reload
      expect(iap_user.subscription_source).to eq('apple_iap')
    end
  end
end
