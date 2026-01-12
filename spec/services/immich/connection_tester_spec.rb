# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::ConnectionTester do
  subject(:service) { described_class.new(url, api_key) }

  let(:url) { 'https://immich.example.com' }
  let(:api_key) { 'test_api_key_123' }

  describe '#call' do
    context 'with missing URL' do
      let(:url) { nil }

      it 'returns error for missing URL' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Immich URL is missing')
      end
    end

    context 'with blank URL' do
      let(:url) { '' }

      it 'returns error for blank URL' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Immich URL is missing')
      end
    end

    context 'with missing API key' do
      let(:api_key) { nil }

      it 'returns error for missing API key' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Immich API key is missing')
      end
    end

    context 'with blank API key' do
      let(:api_key) { '' }

      it 'returns error for blank API key' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Immich API key is missing')
      end
    end

    context 'with successful connection' do
      let(:metadata_response) do
        instance_double(HTTParty::Response, success?: true, code: 200, body: metadata_body)
      end
      let(:metadata_body) do
        { 'assets' => { 'items' => [{ 'id' => 'asset-123' }] } }.to_json
      end
      let(:thumbnail_response) do
        instance_double(HTTParty::Response, success?: true, code: 200)
      end

      before do
        allow(HTTParty).to receive(:post).and_return(metadata_response)
        allow(HTTParty).to receive(:get).and_return(thumbnail_response)
      end

      it 'returns success when both metadata and thumbnail requests succeed' do
        result = service.call
        expect(result[:success]).to be true
        expect(result[:message]).to eq('Immich connection verified')
      end

      it 'makes POST request to metadata endpoint with correct parameters' do
        expect(HTTParty).to receive(:post).with(
          "#{url}/api/search/metadata",
          hash_including(
            headers: { 'x-api-key' => api_key, 'accept' => 'application/json' },
            timeout: 10
          )
        )
        service.call
      end

      it 'makes GET request to thumbnail endpoint with asset ID' do
        expect(HTTParty).to receive(:get).with(
          "#{url}/api/assets/asset-123/thumbnail?size=preview",
          hash_including(
            headers: { 'x-api-key' => api_key, 'accept' => 'application/octet-stream' },
            timeout: 10
          )
        )
        service.call
      end
    end

    context 'when metadata request returns no assets' do
      let(:metadata_response) do
        instance_double(HTTParty::Response, success?: true, code: 200, body: empty_body)
      end
      let(:empty_body) { { 'assets' => { 'items' => [] } }.to_json }

      before do
        allow(HTTParty).to receive(:post).and_return(metadata_response)
      end

      it 'returns success without checking thumbnail' do
        result = service.call
        expect(result[:success]).to be true
        expect(result[:message]).to eq('Immich connection verified')
      end

      it 'does not make thumbnail request' do
        expect(HTTParty).not_to receive(:get)
        service.call
      end
    end

    context 'when metadata request fails' do
      let(:metadata_response) do
        instance_double(HTTParty::Response, success?: false, code: 401)
      end

      before do
        allow(HTTParty).to receive(:post).and_return(metadata_response)
      end

      it 'returns error with status code' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Immich connection failed: 401')
      end
    end

    context 'when thumbnail request fails with 403 and asset.view permission error' do
      let(:metadata_response) do
        instance_double(HTTParty::Response, success?: true, code: 200, body: metadata_body)
      end
      let(:metadata_body) do
        { 'assets' => { 'items' => [{ 'id' => 'asset-123' }] } }.to_json
      end
      let(:thumbnail_response) do
        instance_double(
          HTTParty::Response,
          success?: false,
          code: 403,
          body: { 'message' => 'Missing permission: asset.view' }.to_json
        )
      end

      before do
        allow(HTTParty).to receive(:post).and_return(metadata_response)
        allow(HTTParty).to receive(:get).and_return(thumbnail_response)
      end

      it 'returns specific permission error' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Immich API key missing permission: asset.view')
      end
    end

    context 'when thumbnail request fails with other error' do
      let(:metadata_response) do
        instance_double(HTTParty::Response, success?: true, code: 200, body: metadata_body)
      end
      let(:metadata_body) do
        { 'assets' => { 'items' => [{ 'id' => 'asset-123' }] } }.to_json
      end
      let(:thumbnail_response) do
        instance_double(HTTParty::Response, success?: false, code: 500)
      end

      before do
        allow(HTTParty).to receive(:post).and_return(metadata_response)
        allow(HTTParty).to receive(:get).and_return(thumbnail_response)
      end

      it 'returns thumbnail check failed error' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Immich thumbnail check failed: 500')
      end
    end

    context 'when network timeout occurs' do
      before do
        allow(HTTParty).to receive(:post).and_raise(Net::OpenTimeout)
      end

      it 'returns timeout error' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Immich connection failed: /)
      end
    end

    context 'when JSON parsing fails' do
      let(:metadata_response) do
        instance_double(HTTParty::Response, success?: true, code: 200, body: 'invalid json')
      end

      before do
        allow(HTTParty).to receive(:post).and_return(metadata_response)
      end

      it 'handles JSON parse error gracefully' do
        result = service.call
        expect(result[:success]).to be true
        expect(result[:message]).to eq('Immich connection verified')
      end
    end

    context 'with malformed response body' do
      let(:metadata_response) do
        instance_double(HTTParty::Response, success?: true, code: 200, body: '{}')
      end

      before do
        allow(HTTParty).to receive(:post).and_return(metadata_response)
      end

      it 'handles missing assets key gracefully' do
        result = service.call
        expect(result[:success]).to be true
        expect(result[:message]).to eq('Immich connection verified')
      end
    end
  end
end
