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

    # These call #perform directly: `retry_on` makes ActiveJob swallow the
    # exception even under perform_now, so a raise_error expectation against the
    # job wrapper would pass vacuously whatever #perform did.
    it 'reports and re-raises when Partnero is unreachable so Sidekiq retries' do
      allow(HTTParty).to receive(:post).and_raise(Errno::ECONNREFUSED)
      expect(ExceptionReporter).to receive(:call)

      expect { described_class.new.perform(user.id, partner_key) }.to raise_error(Errno::ECONNREFUSED)
    end

    it 'raises on a rejected API key so the failure is not silent' do
      allow(HTTParty).to receive(:post).and_return(
        instance_double(HTTParty::Response, success?: false, code: 401, body: 'Unauthorized')
      )
      expect(ExceptionReporter).to receive(:call)

      expect { described_class.new.perform(user.id, partner_key) }
        .to raise_error(Partnero::CustomerSignupJob::AttributionFailed, /401/)
    end

    it 'raises on an unknown partner key' do
      allow(HTTParty).to receive(:post).and_return(
        instance_double(HTTParty::Response, success?: false, code: 422, body: 'Unknown partner')
      )
      allow(ExceptionReporter).to receive(:call)

      expect { described_class.new.perform(user.id, partner_key) }
        .to raise_error(Partnero::CustomerSignupJob::AttributionFailed)
    end

    it 'treats an already-registered customer as success' do
      allow(HTTParty).to receive(:post).and_return(
        instance_double(HTTParty::Response, success?: false, code: 409, body: 'Customer already exists')
      )

      expect { described_class.new.perform(user.id, partner_key) }.not_to raise_error
    end

    it 'retries transient failures instead of dropping the commission' do
      handled = described_class.rescue_handlers.map(&:first)

      expect(handled).to include(
        'Net::OpenTimeout', 'Net::ReadTimeout', 'SocketError',
        'Errno::ECONNREFUSED', 'Partnero::CustomerSignupJob::AttributionFailed'
      )
    end

    it 'bounds the request so a hung endpoint cannot park the queue' do
      expect(HTTParty).to receive(:post).with(
        anything, hash_including(timeout: described_class::HTTP_TIMEOUT_SECONDS)
      ).and_return(instance_double(HTTParty::Response, success?: true, code: 200))

      described_class.perform_now(user.id, partner_key)
    end
  end
end
