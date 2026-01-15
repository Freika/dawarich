# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photoprism::ConnectionTester do
  subject(:service) { described_class.new(url, api_key) }

  let(:url) { 'https://photoprism.example.com' }
  let(:api_key) { 'test_api_key_123' }

  describe '#call' do
    context 'with missing URL' do
      let(:url) { nil }

      it 'returns error for missing URL' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Photoprism URL is missing')
      end
    end

    context 'with blank URL' do
      let(:url) { '' }

      it 'returns error for blank URL' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Photoprism URL is missing')
      end
    end

    context 'with missing API key' do
      let(:api_key) { nil }

      it 'returns error for missing API key' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Photoprism API key is missing')
      end
    end

    context 'with blank API key' do
      let(:api_key) { '' }

      it 'returns error for blank API key' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Photoprism API key is missing')
      end
    end

    context 'with successful connection' do
      let(:response) do
        instance_double(HTTParty::Response, success?: true, code: 200)
      end

      before do
        allow(HTTParty).to receive(:get).and_return(response)
      end

      it 'returns success' do
        result = service.call
        expect(result[:success]).to be true
        expect(result[:message]).to eq('Photoprism connection verified')
      end

      it 'makes GET request with correct parameters' do
        expect(HTTParty).to receive(:get).with(
          "#{url}/api/v1/photos",
          hash_including(
            headers: { 'Authorization' => "Bearer #{api_key}", 'accept' => 'application/json' },
            query: { count: 1, public: true },
            timeout: 10
          )
        )
        service.call
      end
    end

    context 'when connection fails with 401' do
      let(:response) do
        instance_double(HTTParty::Response, success?: false, code: 401)
      end

      before do
        allow(HTTParty).to receive(:get).and_return(response)
      end

      it 'returns error with status code' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Photoprism connection failed: 401')
      end
    end

    context 'when connection fails with 500' do
      let(:response) do
        instance_double(HTTParty::Response, success?: false, code: 500)
      end

      before do
        allow(HTTParty).to receive(:get).and_return(response)
      end

      it 'returns error with status code' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Photoprism connection failed: 500')
      end
    end

    context 'when network timeout occurs' do
      before do
        allow(HTTParty).to receive(:get).and_raise(Net::OpenTimeout)
      end

      it 'returns timeout error' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Photoprism connection failed: /)
      end
    end

    context 'when read timeout occurs' do
      before do
        allow(HTTParty).to receive(:get).and_raise(Net::ReadTimeout)
      end

      it 'returns timeout error' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Photoprism connection failed: /)
      end
    end

    context 'when HTTParty error occurs' do
      before do
        allow(HTTParty).to receive(:get).and_raise(HTTParty::Error.new('Connection refused'))
      end

      it 'returns connection error' do
        result = service.call
        expect(result[:success]).to be false
        expect(result[:error]).to match(/Photoprism connection failed: /)
      end
    end
  end
end
