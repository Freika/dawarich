# frozen_string_literal: true

require 'rails_helper'
require 'httpx/adapters/webmock'

RSpec.describe Families::PushNotification do
  let(:subscription) do
    PushSubscription.new(provider: 'apns', environment: 'production', push_token: 'a' * 64)
  end
  let(:payload) do
    { title: 'Location request', body: 'Open Dawarich to respond.', sound: 'default', ttl: 3600,
      data: { type: 'family_location_request', request_id: 12, user_id: 42, context_id: 'opaque-context' } }
  end
  let(:ec_key) { OpenSSL::PKey::EC.generate('prime256v1') }
  let(:rsa_key) { OpenSSL::PKey::RSA.new(2048) }
  let(:credentials) do
    { project_id: 'test-project', client_email: 'test@example.test', private_key: rsa_key.to_pem }
  end
  let(:apns_url) { "https://api.push.apple.com/3/device/#{subscription.push_token}" }
  let(:fcm_url) { 'https://fcm.googleapis.com/v1/projects/test-project/messages:send' }

  before do
    stub_const('PushSubscription::RELEASE_ENABLED', true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    { 'APNS_KEY_ID' => 'KEY123', 'APNS_TEAM_ID' => 'TEAM123', 'APNS_TOPIC' => 'app.dawarich.Dawarich',
      'APNS_PRIVATE_KEY' => ec_key.to_pem, 'FCM_SERVICE_ACCOUNT_JSON' => credentials.to_json,
      'FAMILY_PUSH_ENABLED' => 'true' }.each do |key, value|
      allow(ENV).to receive(:[]).with(key).and_return(value)
      allow(ENV).to receive(:fetch).with(key).and_return(value)
    end
    PushNotifications::Apns::TOKEN_CACHE.clear
    PushNotifications::Fcm::TOKEN_CACHE.clear
  end

  it 'advertises only configured providers when explicitly enabled' do
    expect(PushSubscription.enabled_providers).to eq(%w[apns fcm])
    allow(ENV).to receive(:[]).with('APNS_PRIVATE_KEY').and_return(nil)
    expect(PushSubscription.enabled_providers).to eq(['fcm'])
    allow(ENV).to receive(:[]).with('FAMILY_PUSH_ENABLED').and_return(nil)
    expect(PushSubscription.enabled_providers).to eq([])
  end

  it 'signs APNs requests and supplies the native library routing payload without silent delivery' do
    delivery = stub_request(:post, apns_url).with do |request|
      token = request.headers.fetch('Authorization').split.last
      claims, header = JWT.decode(token, ec_key, true, algorithm: 'ES256')
      body = JSON.parse(request.body)
      expect(claims['iss']).to eq('TEAM123')
      expect(header['kid']).to eq('KEY123')
      expect(request.headers['Apns-Push-Type']).to eq('alert')
      expect(request.headers['Apns-Topic']).to eq('app.dawarich.Dawarich')
      expect(body['body']).to eq(payload[:data].stringify_keys)
      expect(body['aps']).to eq({ 'alert' => payload.slice(:title, :body).stringify_keys, 'sound' => 'default' })
      true
    end.to_return(status: 200)
    expect(described_class.deliver(subscription, payload)).to eq(:sent)
    expect(delivery).to have_been_requested.once
  end

  it 'uses the APNs sandbox only for development tokens' do
    subscription.environment = 'development'
    sandbox_url = "https://api.sandbox.push.apple.com/3/device/#{subscription.push_token}"
    delivery = stub_request(:post, sandbox_url).to_return(status: 200)
    expect(described_class.deliver(subscription, payload)).to eq(:sent)
    expect(delivery).to have_been_requested.once
  end

  it 'removes unregistered APNs tokens but preserves them on credential and transient failures' do
    stub_request(:post, apns_url).to_return(status: 410, body: { reason: 'Unregistered' }.to_json)
    expect(described_class.deliver(subscription, payload)).to eq(:unregistered)
    [403, 429, 500].each do |status|
      stub_request(:post, apns_url).to_return(status: status, body: { reason: 'ProviderError' }.to_json)
      expect { described_class.deliver(subscription, payload) }.to raise_error(described_class::DeliveryError)
    end
  end

  it 'sanitizes native network errors so a token cannot appear in job logs' do
    stub_request(:post, apns_url).to_timeout
    expect { described_class.deliver(subscription, payload) }.to raise_error(described_class::DeliveryError) do |error|
      expect(error.message).not_to include(subscription.push_token)
      expect(error.cause).to be_nil
    end
  end

  context 'with FCM' do
    before do
      subscription.assign_attributes(provider: 'fcm', environment: nil, push_token: 'native-fcm:token-1234567890')
      stub_request(:post, PushNotifications::Fcm::TOKEN_ENDPOINT).with do |request|
        values = URI.decode_www_form(request.body).to_h
        claims, = JWT.decode(values.fetch('assertion'), rsa_key.public_key, true, algorithm: 'RS256')
        expect(claims['scope']).to eq('https://www.googleapis.com/auth/firebase.messaging')
        expect(claims['aud']).to eq(PushNotifications::Fcm::TOKEN_ENDPOINT)
        true
      end.to_return(status: 200, body: { access_token: 'test-oauth-token', expires_in: 3600 }.to_json)
    end

    it 'sends a visible FCM v1 notification with JSON routing data and caches authorization' do
      headers = { 'Authorization' => 'Bearer test-oauth-token' }
      delivery = stub_request(:post, fcm_url).with(headers: headers) do |request|
        message = JSON.parse(request.body).fetch('message')
        expect(message['notification']).to eq(payload.slice(:title, :body).stringify_keys)
        expect(JSON.parse(message.dig('data', 'body'))).to eq(payload[:data].stringify_keys)
        expect(message.dig('android', 'notification', 'channel_id')).to eq('family-requests')
        expect(message.dig('android', 'ttl')).to eq('3600s')
        true
      end.to_return(status: 200, body: { name: 'projects/test-project/messages/1' }.to_json)
      2.times { expect(described_class.deliver(subscription, payload)).to eq(:sent) }
      expect(delivery).to have_been_requested.twice
      expect(WebMock).to have_requested(:post, PushNotifications::Fcm::TOKEN_ENDPOINT).once
    end

    it 'removes only tokens with a specific UNREGISTERED provider response' do
      stub_request(:post, fcm_url).to_return(status: 404, body: {
        error: { details: [{ '@type' => 'type.googleapis.com/google.firebase.fcm.v1.FcmError',
                            errorCode: 'UNREGISTERED' }] }
      }.to_json)
      expect(described_class.deliver(subscription, payload)).to eq(:unregistered)
      [400, 401, 404, 429, 503].each do |status|
        stub_request(:post, fcm_url).to_return(status: status, body: { error: { status: 'ERROR' } }.to_json)
        expect { described_class.deliver(subscription, payload) }.to raise_error(described_class::DeliveryError)
      end
    end
  end
end
