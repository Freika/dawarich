# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Push subscriptions', type: :request do
  let(:user) { create(:user) }
  let(:installation) { SecureRandom.uuid }
  let(:path) { "/api/v1/push_subscriptions/#{installation}" }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }
  let(:params) { { push_token: 'a' * 64, provider: 'apns', environment: 'production', context_id: SecureRandom.uuid } }

  before { allow(PushSubscription).to receive(:enabled_providers).and_return(%w[apns fcm]) }

  it 'requires a configured native provider' do
    allow(PushSubscription).to receive(:enabled_providers).and_return(['apns'])
    put path, params: params.merge(provider: 'fcm'), headers: headers
    expect(response).to have_http_status(:service_unavailable)
    expect(PushSubscription.count).to eq(0)
  end

  it 'validates APNs environments and FCM tokens' do
    put path, params: params.merge(environment: 'https://example.test'), headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    put path, params: params.merge(provider: 'fcm', environment: nil, push_token: 'native-fcm-token:1234567890'),
headers: headers
    expect(response).to have_http_status(:no_content)
    expect(PushSubscription.sole.provider).to eq('fcm')
  end

  it 'requires authentication' do
    put path, params: params
    expect(response).to have_http_status(:unauthorized)
    expect(PushSubscription.count).to eq(0)
  end

  it 'registers, rotates and removes only the authenticated device' do
    put path, params: params, headers: headers
    expect(response).to have_http_status(:no_content)
    expect(PushSubscription.last.deliverable?).to be true
    put path, params: params.merge(push_token: 'b' * 64), headers: headers
    expect(response).to have_http_status(:no_content)
    expect(PushSubscription.where(user: user).count).to eq(1)
    other = create(:user)
    delete path, headers: { 'Authorization' => "Bearer #{other.api_key}" }
    expect(PushSubscription.count).to eq(1)
    delete path, headers: headers
    expect(PushSubscription.count).to eq(0)
  end

  it 'transfers an installation token on account switch and rejects invalid tokens' do
    put path, params: params, headers: headers
    other = create(:user)
    put path, params: params, headers: { 'Authorization' => "Bearer #{other.api_key}" }
    expect(response).to have_http_status(:no_content)
    expect(PushSubscription.sole.user).to eq(other)
    delete path, headers: headers
    expect(PushSubscription.count).to eq(1)
    put path, params: params.merge(push_token: 'https://example.test'), headers: headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(PushSubscription.sole.user).to eq(other)
  end
end
