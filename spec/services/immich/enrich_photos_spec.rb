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

      it 'returns pending count' do
        result = service.call

        expect(result[:enriched]).to eq(0)
        expect(result[:pending]).to eq(2)
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

        expect(result[:enriched]).to eq(0)
        expect(result[:pending]).to eq(1)
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

        expect(result[:enriched]).to eq(0)
        expect(result[:pending]).to eq(1)
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

RSpec.describe Immich::EnrichPhotos, 'request safety' do
  let(:user) { create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' }) }

  it 'escapes the asset id in the request path' do
    request = stub_request(:put, 'http://immich.app/api/assets/..%2Fadmin')
              .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

    described_class.new(user, [{ 'immich_asset_id' => '../admin', 'latitude' => 1.0, 'longitude' => 2.0 }]).call

    expect(request).to have_been_requested
  end

  def error_for(asset_id = 'uuid-1')
    result = described_class.new(user, [{ 'immich_asset_id' => asset_id, 'latitude' => 1.0, 'longitude' => 2.0 }]).call
    result[:errors].first[:error]
  end

  it 'names the underlying network failure, never its message, which can echo a credential' do
    stub_request(:put, 'http://immich.app/api/assets/uuid-1').to_raise(Errno::ECONNREFUSED.new('token=abc'))

    expect(error_for).to include('Errno::ECONNREFUSED')
    expect(error_for).not_to include('token=abc', 'Transport')
  end

  it 'says that the host does not resolve' do
    stub_unresolvable_host('immich.app')

    expect(error_for).to match(/resolve/i)
    expect(error_for).not_to include('BlockedUrlError')
  end

  it 'passes on the redirect hint' do
    stub_request(:put, 'http://immich.app/api/assets/uuid-1')
      .to_return(status: 301, headers: { 'Location' => 'https://immich.app/api/assets/uuid-1' })

    expect(error_for).to include('https://immich.app', 'final URL')
  end
end
