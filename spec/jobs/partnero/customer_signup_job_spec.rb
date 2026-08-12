# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Partnero::CustomerSignupJob, type: :job do
  let(:user) { create(:user, first_name: 'Ada', last_name: 'Lovelace') }
  let(:partner_key) { 'PARTNER123' }
  let(:api_key) { 'partnero-secret' }

  before do
    stub_const('ENV', ENV.to_hash.merge('PARTNERO_API_KEY' => api_key))
    allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, success?: true, code: 200))
  end

  describe '#perform' do
    it 'registers the customer against the referring partner' do
      expect(HTTParty).to receive(:post).with(
        'https://api.partnero.com/v1/customers',
        hash_including(
          headers: hash_including('Authorization' => "Bearer #{api_key}"),
          body: {
            partner: { key: partner_key },
            key: user.id.to_s,
            email: user.email,
            name: 'Ada',
            surname: 'Lovelace'
          }.to_json
        )
      )

      described_class.perform_now(user.id, partner_key)
    end

    it 'does nothing without an API key' do
      stub_const('ENV', ENV.to_hash.merge('PARTNERO_API_KEY' => ''))

      expect(HTTParty).not_to receive(:post)

      described_class.perform_now(user.id, partner_key)
    end

    it 'does nothing without a partner key' do
      expect(HTTParty).not_to receive(:post)

      described_class.perform_now(user.id, nil)
    end

    it 'does nothing when the user no longer exists' do
      expect(HTTParty).not_to receive(:post)

      described_class.perform_now(-1, partner_key)
    end

    it 'does not raise when Partnero is unreachable' do
      allow(HTTParty).to receive(:post).and_raise(Errno::ECONNREFUSED)

      expect { described_class.perform_now(user.id, partner_key) }.not_to raise_error
    end
  end
end
