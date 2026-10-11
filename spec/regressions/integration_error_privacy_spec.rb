# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Integration error privacy' do
  let(:secret) { 'synthetic-provider-secret' }

  describe 'Partnero signup attribution' do
    let(:user) { create(:user, email: 'synthetic-customer@example.com') }

    before do
      stub_const('ENV', ENV.to_hash.merge('PARTNERO_API_KEY' => secret))
      allow(ExceptionReporter).to receive(:call)
    end

    it 'reports only the status when a rejection body echoes customer details and credentials' do
      stub_request(:post, Partnero::CustomerSignupJob::API_URL)
        .to_return(status: 422, body: "#{user.email} #{secret} partner-private")

      expect do
        Partnero::CustomerSignupJob.new.perform(user.id, 'partner-private')
      end.to raise_error(Partnero::CustomerSignupJob::AttributionFailed) { |error|
        expect(error.message).to eq('Partnero rejected the signup (HTTP 422)')
      }

      expect(ExceptionReporter).to have_received(:call) do |error, context|
        expect(error.message).to eq('Partnero rejected the signup (HTTP 422)')
        expect(context).to eq('Partnero signup attribution failed')
      end
    end

    [Net::OpenTimeout, Net::ReadTimeout].each do |error_class|
      it "sanitizes #{error_class} while keeping its retryable exception class" do
        stub_request(:post, Partnero::CustomerSignupJob::API_URL)
          .to_raise(error_class.new("#{secret} #{user.email}"))

        expect do
          Partnero::CustomerSignupJob.new.perform(user.id, 'partner-private')
        end.to raise_error(error_class) { |error|
          expect(error.message).not_to include(secret, user.email)
          expect(error.cause).to be_nil
          expect(error.backtrace).not_to be_empty
        }

        expect(ExceptionReporter).to have_received(:call) do |error, context|
          expect(error.message).not_to include(secret, user.email)
          expect(error.cause).to be_nil
          expect(error.backtrace).not_to be_empty
          expect(context).to eq('Partnero signup attribution failed')
        end
      end
    end
  end

  describe 'Immich photo enrichment' do
    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.test', 'immich_api_key' => secret })
    end
    let(:assets) { [{ 'immich_asset_id' => 'synthetic-asset', 'latitude' => 52.52, 'longitude' => 13.405 }] }

    it 'returns trusted status text when the provider reason phrase echoes a credential' do
      stub_request(:put, 'http://immich.test/api/assets/synthetic-asset')
        .to_return(status: [403, secret], body: secret)

      result = Immich::EnrichPhotos.new(user, assets).call

      expect(result[:failed]).to eq(1)
      expect(result[:errors].first[:error]).to eq('HTTP 403: Forbidden')
      expect(result.to_s).not_to include(secret)
    end

    it 'keeps transport credentials out of the returned error' do
      stub_request(:put, 'http://immich.test/api/assets/synthetic-asset')
        .to_raise(Net::OpenTimeout.new(secret))

      result = Immich::EnrichPhotos.new(user, assets).call

      expect(result[:failed]).to eq(1)
      expect(result[:errors].first[:error]).to be_present
      expect(result.to_s).not_to include(secret)
    end
  end
end
