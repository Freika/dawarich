# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Billing analytics callback', type: :request do
  let(:user) { create(:user, product_analytics_consent: true, product_analytics_id: SecureRandom.uuid) }
  let(:secret) { 'analytics-test-secret' }
  let(:headers) { { 'X-Webhook-Secret' => secret } }
  let(:token) do
    JWT.encode({ user_id: user.id, purpose: 'product_analytics_billing',
                 analytics_event: 'paid_conversion', event_id: SecureRandom.uuid,
                 analytics_properties: { provider: 'apple_iap', plan: 'pro', amount_minor: 999,
                                         currency: 'EUR', amount_eur_minor: 999 },
                 exp: 10.minutes.from_now.to_i }, secret, 'HS256')
  end

  before do
    stub_const('ENV', ENV.to_h.merge('JWT_SECRET_KEY' => secret,
                                     'SUBSCRIPTION_WEBHOOK_SECRET' => secret,
                                     'PRODUCT_POSTHOG_API_KEY' => 'phc_test',
                                     'PRODUCT_POSTHOG_PERSONAL_API_KEY' => 'personal_test',
                                     'PRODUCT_POSTHOG_PROJECT_ID' => '123'))
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    allow(PostHog).to receive(:capture).and_return(true)
  end

  it 'accepts provider-confirmed paid conversion under consent' do
    post '/api/v1/subscriptions/analytics_events', params: { token: token }, headers: headers
    expect(response).to have_http_status(:accepted)
    expect(PostHog).to have_received(:capture).with(hash_including(distinct_id: user.product_analytics_id,
                                                                   event: 'paid_conversion'))
  end

  it 'does not capture when consent is withdrawn' do
    user.update!(product_analytics_consent: false, product_analytics_id: nil)
    post '/api/v1/subscriptions/analytics_events', params: { token: token }, headers: headers
    expect(response).to have_http_status(:no_content)
    expect(PostHog).not_to have_received(:capture)
  end

  it 'rejects a client without the manager secret' do
    post '/api/v1/subscriptions/analytics_events', params: { token: token }
    expect(response).to have_http_status(:unauthorized)
  end
end
