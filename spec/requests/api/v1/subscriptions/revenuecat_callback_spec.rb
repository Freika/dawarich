require 'rails_helper'

RSpec.describe 'POST /api/v1/subscriptions/callback (RevenueCat)', type: :request do
  let(:user) { create(:user, status: :pending_payment) }

  before do
    ENV['REVENUECAT_WEBHOOK_SECRET'] = 'revcat-secret'
    # Set manager secret too so the Paddle-path smoke test doesn't short-circuit on 503.
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
        type: 'INITIAL_PURCHASE',
        app_user_id: user.id.to_s,
        product_id: 'dawarich.pro.yearly',
        expiration_at_ms: 7.days.from_now.to_i * 1000,
        store: 'APP_STORE'
      }
    }
  end

  it 'updates user on valid RevenueCat webhook' do
    post '/api/v1/subscriptions/callback',
         params: payload.to_json,
         headers: { 'Content-Type' => 'application/json', 'Authorization' => 'revcat-secret' }

    expect(response).to have_http_status(:ok)
    user.reload
    expect(user.status).to eq('trial')
    expect(user.subscription_source).to eq('apple_iap')
  end

  it 'returns 401 on wrong Authorization header' do
    post '/api/v1/subscriptions/callback',
         params: payload.to_json,
         headers: { 'Content-Type' => 'application/json', 'Authorization' => 'wrong-secret' }

    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 503 if secret env not configured' do
    ENV.delete('REVENUECAT_WEBHOOK_SECRET')
    post '/api/v1/subscriptions/callback',
         params: payload.to_json,
         headers: { 'Content-Type' => 'application/json', 'Authorization' => 'anything' }

    expect(response).to have_http_status(:service_unavailable)
  end

  it 'leaves the existing Paddle JWT path working (smoke test)' do
    # The Paddle path still expects a `token` param with a JWT.
    # This is a placeholder to catch a regression where we accidentally blocked it.
    post '/api/v1/subscriptions/callback', params: { token: 'obviously-bad-jwt' }
    # We don't care about the exact status here — just that it doesn't crash with 500.
    expect(response.status).to be < 500
  end
end
