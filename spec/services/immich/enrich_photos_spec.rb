# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::EnrichPhotos do
  describe '#call' do
    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end

    let(:assets) do
      [
        { 'immich_asset_id' => 'uuid-1', 'latitude' => 52.52, 'longitude' => 13.405 },
        { 'immich_asset_id' => 'uuid-2', 'latitude' => 48.85, 'longitude' => 2.35 }
      ]
    end

    subject(:service) { described_class.new(user, assets) }

    context 'when all updates succeed' do
      before do
        stub_request(:put, 'http://immich.app/api/assets/uuid-1')
          .to_return(status: 200, body: '{}', headers: { 'content-type' => 'application/json' })
        stub_request(:put, 'http://immich.app/api/assets/uuid-2')
          .to_return(status: 200, body: '{}', headers: { 'content-type' => 'application/json' })
      end

      it 'returns enriched count' do
        result = service.call

        expect(result[:enriched]).to eq(2)
        expect(result[:failed]).to eq(0)
        expect(result[:errors]).to be_empty
      end

      it 'sends PUT requests with correct coordinates' do
        service.call

        expect(WebMock).to have_requested(:put, 'http://immich.app/api/assets/uuid-1')
          .with(body: { latitude: 52.52, longitude: 13.405 }.to_json)
        expect(WebMock).to have_requested(:put, 'http://immich.app/api/assets/uuid-2')
          .with(body: { latitude: 48.85, longitude: 2.35 }.to_json)
      end

      it 'includes correct headers' do
        service.call

        expect(WebMock).to have_requested(:put, 'http://immich.app/api/assets/uuid-1')
          .with(headers: { 'x-api-key' => '123456', 'Content-Type' => 'application/json' })
      end
    end

    context 'when some updates fail' do
      before do
        stub_request(:put, 'http://immich.app/api/assets/uuid-1')
          .to_return(status: 200, body: '{}', headers: { 'content-type' => 'application/json' })
        stub_request(:put, 'http://immich.app/api/assets/uuid-2')
          .to_return(status: 403, body: '{"message": "Missing permission: asset.update"}',
                     headers: { 'content-type' => 'application/json' })
      end

      it 'returns partial results' do
        result = service.call

        expect(result[:enriched]).to eq(1)
        expect(result[:failed]).to eq(1)
      end

      it 'includes error details for failed assets' do
        result = service.call
        error = result[:errors].first

        expect(error[:immich_asset_id]).to eq('uuid-2')
        expect(error[:error]).to be_present
      end
    end

    context 'when network error occurs' do
      before do
        stub_request(:put, 'http://immich.app/api/assets/uuid-1')
          .to_timeout
        stub_request(:put, 'http://immich.app/api/assets/uuid-2')
          .to_return(status: 200, body: '{}', headers: { 'content-type' => 'application/json' })
      end

      it 'continues processing remaining assets after failure' do
        result = service.call

        expect(result[:enriched]).to eq(1)
        expect(result[:failed]).to eq(1)
      end
    end

    context 'when assets list is empty' do
      let(:assets) { [] }

      it 'returns zero counts' do
        result = service.call

        expect(result[:enriched]).to eq(0)
        expect(result[:failed]).to eq(0)
      end
    end

    context 'when Immich credentials are missing' do
      let(:user) { create(:user, settings: {}) }

      it 'returns error' do
        result = service.call

        expect(result[:error]).to be_present
      end
    end
  end
end
