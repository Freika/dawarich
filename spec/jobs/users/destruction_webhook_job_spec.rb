# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::DestructionWebhookJob, type: :job do
  let(:user_id) { 12_345 }
  let(:email) { 'gone@example.com' }
  let(:jwt_token) { 'encoded.jwt.token' }
  let(:webhook_host) { 'https://example-webhook.test' }
  let(:request_url) { "#{webhook_host}/api/v1/users/unlink" }
  let(:jwt_service) { instance_double(Subscription::EncodeJwtToken, call: jwt_token) }

  before do
    stub_const('ENV', ENV.to_hash.merge('MANAGER_URL' => webhook_host, 'JWT_SECRET_KEY' => 'secret'))
    allow(Subscription::EncodeJwtToken).to receive(:new).and_return(jwt_service)
    allow(HTTParty).to receive(:post)
  end

  describe '#perform' do
    it 'encodes JWT with destroy_user action and identifying fields' do
      expected_payload = {
        user_id: user_id,
        email: email,
        action: 'destroy_user'
      }

      expect(Subscription::EncodeJwtToken).to receive(:new)
        .with(expected_payload, 'secret')
        .and_return(jwt_service)

      described_class.perform_now(user_id, email)
    end

    it 'POSTs the JWT to the unlink webhook endpoint with a finite timeout' do
      expected_headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
      expected_body = { token: jwt_token }.to_json

      expect(HTTParty).to receive(:post)
        .with(request_url,
              headers: expected_headers,
              body: expected_body,
              timeout: described_class::HTTP_TIMEOUT_SECONDS)

      described_class.perform_now(user_id, email)
    end

    context 'when the HTTP call raises a non-retryable error' do
      it 'reports to ExceptionReporter and re-raises' do
        boom = RuntimeError.new('manager unreachable')
        allow(HTTParty).to receive(:post).and_raise(boom)
        allow(ExceptionReporter).to receive(:call)

        expect { described_class.perform_now(user_id, email) }
          .to raise_error(RuntimeError, 'manager unreachable')
        expect(ExceptionReporter).to have_received(:call)
          .with(boom, /user_id=#{user_id}/)
      end
    end

    context 'when MANAGER_URL is not configured (self-hosted)' do
      before { stub_const('ENV', ENV.to_hash.merge('MANAGER_URL' => nil, 'JWT_SECRET_KEY' => 'secret')) }

      it 'does not make any HTTP request' do
        expect(HTTParty).not_to receive(:post)

        described_class.perform_now(user_id, email)
      end
    end
  end
end
