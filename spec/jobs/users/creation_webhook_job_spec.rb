# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::CreationWebhookJob, type: :job do
  let(:user) { create(:user, :trial, first_name: 'Ada', last_name: 'Lovelace') }
  let(:jwt_token) { 'encoded.jwt.token' }
  let(:manager_url) { 'https://manager.example.com' }
  let(:request_url) { "#{manager_url}/api/v1/users" }
  let(:jwt_service) { instance_double(Subscription::EncodeJwtToken, call: jwt_token) }

  before do
    stub_const('ENV', ENV.to_hash.merge('MANAGER_URL' => manager_url, 'JWT_SECRET_KEY' => 'secret'))
    allow(Subscription::EncodeJwtToken).to receive(:new).and_return(jwt_service)
    allow(HTTParty).to receive(:post)
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
        .with(request_url, headers: expected_headers, body: expected_body)

      described_class.perform_now(user.id)
    end

    it 'serializes status and configured zone in the signed manager claims' do
      user.update_columns(status: 2, active_until: Time.utc(2026, 10, 6, 12, 0, 0, 123_456))
      user.reload
      allow(Subscription::EncodeJwtToken).to receive(:new).and_call_original

      { 'Europe/Berlin' => '2026-10-06 14:00:00 +0200',
        'UTC' => '2026-10-06 12:00:00 UTC' }.each do |zone, expected|
        expect(HTTParty).to receive(:post) do |_url, options|
          token = JSON.parse(options[:body]).fetch('token')
          claims = JWT.decode(token, 'secret', true, algorithm: 'HS256').first
          expect(claims.fetch('status')).to eq('trial')
          expect(claims.fetch('active_until')).to eq(expected)
          expect(claims.fetch('action')).to eq('create_user')
        end

        Time.use_zone(zone) { described_class.new.perform(user.id) }
      end
    end

    it 'ignores a rejected HTTP response without retrying' do
      allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, code: 500))

      expect { described_class.new.perform(user.id) }.not_to raise_error
      expect(HTTParty).to have_received(:post).once
    end

    it 'propagates transport errors to the job runner' do
      allow(HTTParty).to receive(:post).and_raise(Net::ReadTimeout)

      expect { described_class.new.perform(user.id) }.to raise_error(Net::ReadTimeout)
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
