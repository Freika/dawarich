require 'rails_helper'

RSpec.describe Users::TrialWebhookJob, type: :job do
  let(:user) { create(:user, :trial) }
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

    context 'when user is deleted' do
      it 'raises ActiveRecord::RecordNotFound' do
        user.destroy

        expect {
          described_class.perform_now(user.id)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
