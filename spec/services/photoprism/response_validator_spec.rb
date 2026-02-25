# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photoprism::ResponseValidator do
  describe '.validate_and_parse' do
    let(:logger) { instance_double(ActiveSupport::Logger) }

    before do
      allow(logger).to receive(:error)
    end

    context 'with successful JSON response' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          body: '{"key": "value"}',
          headers: { 'content-type' => 'application/json' }
        )
      end

      it 'returns success with parsed data' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be true
        expect(result[:data]).to eq({ 'key' => 'value' })
      end
    end

    context 'with failed HTTP status' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: false,
          code: 401,
          body: 'Unauthorized',
          headers: { 'content-type' => 'text/html' }
        )
      end

      it 'returns failure with status code error' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Request failed: 401')
      end
    end

    context 'with non-JSON content type' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          body: '<html>Error page</html>',
          headers: { 'content-type' => 'text/html' }
        )
      end

      it 'returns failure with content type error' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Expected JSON, got text/html')
      end

      it 'logs the error' do
        described_class.validate_and_parse(response, logger: logger)

        expect(logger).to have_received(:error).with(/Photoprism returned non-JSON response/)
      end
    end

    context 'with malformed JSON' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          body: 'not valid json {',
          headers: { 'content-type' => 'application/json' }
        )
      end

      it 'returns failure with parse error' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid JSON response')
      end

      it 'logs the parse error' do
        described_class.validate_and_parse(response, logger: logger)

        expect(logger).to have_received(:error).with(/Photoprism JSON parse error/)
      end
    end

    context 'with empty content-type header' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          body: '{"data": []}',
          headers: {}
        )
      end

      it 'returns failure when content-type is missing' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Expected JSON, got unknown')
      end
    end

    context 'with very large response body' do
      let(:large_body) { 'x' * 2000 }
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          body: large_body,
          headers: { 'content-type' => 'text/html' }
        )
      end

      it 'truncates the body in logs' do
        described_class.validate_and_parse(response, logger: logger)

        expect(logger).to have_received(:error) do |message|
          expect(message).to include('truncated')
          expect(message.length).to be < large_body.length + 100
        end
      end
    end

    context 'with case-insensitive content-type header' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          body: '{"data": "value"}',
          headers: { 'Content-Type' => 'application/json; charset=utf-8' }
        )
      end

      it 'handles Content-Type with different case' do
        result = described_class.validate_and_parse(response, logger: logger)

        expect(result[:success]).to be true
        expect(result[:data]).to eq({ 'data' => 'value' })
      end
    end
  end
end
