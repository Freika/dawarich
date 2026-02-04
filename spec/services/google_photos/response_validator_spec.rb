# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GooglePhotos::ResponseValidator do
  describe '.validate_and_parse' do
    let(:logger) { instance_double(Logger, error: nil) }

    context 'when response is successful with JSON content' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          body: '{"mediaItems": []}',
          headers: { 'content-type' => 'application/json' }
        )
      end

      it 'returns success with parsed data' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be true
        expect(result[:data]).to eq({ 'mediaItems' => [] })
      end
    end

    context 'when response is not successful' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: false,
          code: 401
        )
      end

      it 'returns error with status code' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Request failed: 401')
      end
    end

    context 'when response is not JSON' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          body: '<html>Error</html>',
          code: 200,
          headers: { 'content-type' => 'text/html' }
        )
      end

      it 'returns error about content type' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Expected JSON')
      end
    end

    context 'when JSON is invalid' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          body: 'invalid json',
          headers: { 'content-type' => 'application/json' }
        )
      end

      it 'returns JSON parse error' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid JSON response')
      end
    end
  end
end
