# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::CreationWebhookJob, type: :job do
  let(:user) { create(:user, :trial, first_name: 'Ada', last_name: 'Lovelace') }
  let(:jwt_token) { 'encoded.jwt.token' }
  let(:manager_url) { 'https://manager.example.com' }
  let(:request_url) { "#{manager_url}/api/v1/users" }
  let(:jwt_service) { instance_double(Subscription::EncodeJwtToken, call: jwt_token) }
  let(:success_response) { instance_double(HTTParty::Response, success?: true, code: 200, body: '{}') }

  before do
    stub_const('ENV', ENV.to_hash.merge('MANAGER_URL' => manager_url, 'JWT_SECRET_KEY' => 'secret'))
    allow(Subscription::EncodeJwtToken).to receive(:new).and_return(jwt_service)
    allow(HTTParty).to receive(:post).and_return(success_response)
  end

  describe '#perform' do
    it 'encodes JWT with correct payload' do
      expected_payload = {
        user_id: user.id,
        email: user.email,
        first_name: 'Ada',
        last_name: 'Lovelace',
        active_until: user.active_until,
        status: user.status,
        action: 'create_user'
      }

      expect(Subscription::EncodeJwtToken).to receive(:new)
        .with(expected_payload, 'secret')
        .and_return(jwt_service)

      described_class.perform_now(user.id)
    end

    it 'makes HTTP POST request to Manager API' do
      expected_headers = {
        'Content-Type' => 'application/json',
        'Accept' => 'application/json'
      }
      expected_body = { token: jwt_token }.to_json

      expect(HTTParty).to receive(:post)
        .with(request_url, headers: expected_headers, body: expected_body,
                           timeout: described_class::HTTP_TIMEOUT_SECONDS)
        .and_return(success_response)

      described_class.perform_now(user.id)
    end

    it 'sets an explicit HTTP timeout' do
      expect(described_class::HTTP_TIMEOUT_SECONDS).to be_a(Integer)
      expect(described_class::HTTP_TIMEOUT_SECONDS).to be_positive
    end

    context 'when Manager rejects the webhook' do
      let(:error_response) { instance_double(HTTParty::Response, success?: false, code: 500, body: 'boom') }

      before { allow(HTTParty).to receive(:post).and_return(error_response) }

      it 'raises so Sidekiq retries instead of silently dropping the user' do
        expect { described_class.perform_now(user.id) }.to raise_error(described_class::WebhookDeliveryError, /500/)
      end
    end

    context 'when Manager accepts the webhook' do
      it 'completes without raising' do
        expect { described_class.perform_now(user.id) }.not_to raise_error
      end
    end

    describe 'retry configuration' do
      it 'retries on transient network failures' do
        %w[Net::OpenTimeout Net::ReadTimeout SocketError Errno::ECONNREFUSED].each do |error_class|
          expect(described_class.rescue_handlers.map(&:first)).to include(error_class)
        end
      end
    end

    context 'when user is deleted' do
      before { user.mark_as_deleted! }

      it 'skips the webhook for soft-deleted users' do
        expect(HTTParty).not_to receive(:post)

        described_class.perform_now(user.id)
      end
    end

    context 'when user does not exist' do
      it 'does not raise error' do
        expect(HTTParty).not_to receive(:post)

        expect { described_class.perform_now(999_999) }.not_to raise_error
      end
    end

    context 'when MANAGER_URL is blank' do
      before { stub_const('ENV', ENV.to_hash.merge('MANAGER_URL' => '')) }

      it 'skips the webhook' do
        expect(HTTParty).not_to receive(:post)

        described_class.perform_now(user.id)
      end
    end
  end
end
