# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::ResponseValidator do
  describe '.validate_and_parse' do
    let(:logger) { instance_double(ActiveSupport::Logger) }

    context 'with successful JSON response' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          headers: { 'content-type' => 'application/json' },
          body: { 'assets' => { 'items' => [] } }.to_json
        )
      end

      it 'returns success with parsed data' do
        result = described_class.validate_and_parse(response)
        expect(result[:success]).to be true
        expect(result[:data]).to eq({ 'assets' => { 'items' => [] } })
        expect(result[:error]).to be_nil
      end
    end

    context 'with failed HTTP status' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: false,
          code: 401
        )
      end

      it 'returns failure with status code' do
        result = described_class.validate_and_parse(response)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Request failed: 401')
      end
    end

    context 'with non-JSON content-type' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          headers: { 'content-type' => 'text/html' },
          body: '<html><body>Error</body></html>'
        )
      end

      before do
        allow(logger).to receive(:error)
      end

      it 'returns failure with content-type error' do
        result = described_class.validate_and_parse(response, logger: logger)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Expected JSON, got text/html')
      end

      it 'logs the non-JSON response' do
        expect(logger).to receive(:error).with(/Immich returned non-JSON response/)
        described_class.validate_and_parse(response, logger: logger)
      end
    end

    context 'with malformed JSON' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          headers: { 'content-type' => 'application/json' },
          body: '{"invalid": json}'
        )
      end

      before do
        allow(logger).to receive(:error)
      end

      it 'returns failure with parse error' do
        result = described_class.validate_and_parse(response, logger: logger)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid JSON response')
      end

      it 'logs the parse error and body' do
        expect(logger).to receive(:error).with(/Immich JSON parse error/)
        expect(logger).to receive(:error).with(/Response body:/)
        described_class.validate_and_parse(response, logger: logger)
      end
    end

    context 'with very large response body' do
      let(:long_body) { 'x' * 2000 }
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          headers: { 'content-type' => 'application/json' },
          body: long_body
        )
      end

      before do
        allow(logger).to receive(:error)
      end

      it 'truncates the logged body' do
        expect(logger).to receive(:error).with(/Immich JSON parse error/)
        expect(logger).to receive(:error).with(/\(truncated\)/)
        described_class.validate_and_parse(response, logger: logger)
      end
    end

    context 'with case-insensitive content-type header' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          success?: true,
          code: 200,
          headers: { 'Content-Type' => 'application/json; charset=utf-8' },
          body: { 'data' => 'value' }.to_json
        )
      end

      it 'accepts mixed case content-type' do
        result = described_class.validate_and_parse(response)
        expect(result[:success]).to be true
      end
    end
  end

  describe '.validate_and_parse_body' do
    let(:logger) { instance_double(ActiveSupport::Logger) }

    context 'with valid JSON string' do
      let(:body) { { 'assets' => { 'items' => [{ 'id' => '123' }] } }.to_json }

      it 'returns success with parsed data' do
        result = described_class.validate_and_parse_body(body)
        expect(result[:success]).to be true
        expect(result[:data]['assets']['items'].first['id']).to eq('123')
      end
    end

    context 'with malformed JSON string' do
      let(:body) { '{"invalid": }' }

      before do
        allow(logger).to receive(:error)
      end

      it 'returns failure' do
        result = described_class.validate_and_parse_body(body, logger: logger)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid JSON')
      end

      it 'logs the error and body' do
        expect(logger).to receive(:error).with(/JSON parse error/)
        expect(logger).to receive(:error).with(/Body:/)
        described_class.validate_and_parse_body(body, logger: logger)
      end
    end

    context 'with nil body' do
      it 'returns failure without logging' do
        result = described_class.validate_and_parse_body(nil, logger: logger)
        expect(result[:success]).to be false
        expect(result[:error]).to eq('Invalid JSON')
      end

      it 'does not log error for nil body' do
        expect(logger).not_to receive(:error)
        described_class.validate_and_parse_body(nil, logger: logger)
      end
    end

    context 'with long body string' do
      let(:body) { 'x' * 2000 }

      before do
        allow(logger).to receive(:error)
      end

      it 'truncates logged body' do
        expect(logger).to receive(:error).exactly(2).times do |message|
          expect(message.length).to be < 1100 if message.include?('Body:')
        end
        described_class.validate_and_parse_body(body, logger: logger)
      end
    end
  end
end
