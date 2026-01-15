# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::ResponseAnalyzer do
  subject(:analyzer) { described_class.new(response) }

  describe '#permission_error?' do
    context 'with 403 response containing asset.view permission error' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 403,
          body: { 'message' => 'Missing permission: asset.view' }.to_json
        )
      end

      it 'returns true' do
        expect(analyzer.permission_error?).to be true
      end
    end

    context 'with 403 response containing different permission error' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 403,
          body: { 'message' => 'Missing permission: album.read' }.to_json
        )
      end

      it 'returns false' do
        expect(analyzer.permission_error?).to be false
      end
    end

    context 'with 403 response but no asset.view in message' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 403,
          body: { 'message' => 'Forbidden' }.to_json
        )
      end

      it 'returns false' do
        expect(analyzer.permission_error?).to be false
      end
    end

    context 'with 403 response but malformed JSON' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 403,
          body: 'invalid json'
        )
      end

      it 'returns false' do
        expect(analyzer.permission_error?).to be false
      end
    end

    context 'with 403 response but no message field' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 403,
          body: { 'error' => 'Forbidden' }.to_json
        )
      end

      it 'returns false' do
        expect(analyzer.permission_error?).to be false
      end
    end

    context 'with non-403 response' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 401,
          body: { 'message' => 'Unauthorized' }.to_json
        )
      end

      it 'returns false' do
        expect(analyzer.permission_error?).to be false
      end
    end

    context 'with 200 success response' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 200,
          body: { 'data' => 'some data' }.to_json
        )
      end

      it 'returns false' do
        expect(analyzer.permission_error?).to be false
      end
    end

    context 'with string code instead of integer' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: '403',
          body: { 'message' => 'Missing permission: asset.view' }.to_json
        )
      end

      it 'returns true' do
        expect(analyzer.permission_error?).to be true
      end
    end
  end

  describe '#error_message' do
    context 'when permission_error? is true' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 403,
          body: { 'message' => 'Missing permission: asset.view' }.to_json
        )
      end

      it 'returns specific permission error message' do
        expect(analyzer.error_message).to eq('Immich API key missing permission: asset.view')
      end
    end

    context 'when permission_error? is false' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 401,
          body: { 'message' => 'Unauthorized' }.to_json
        )
      end

      it 'returns generic error message' do
        expect(analyzer.error_message).to eq('Failed to fetch thumbnail')
      end
    end

    context 'with 500 error' do
      let(:response) do
        instance_double(
          HTTParty::Response,
          code: 500,
          body: { 'error' => 'Internal Server Error' }.to_json
        )
      end

      it 'returns generic error message' do
        expect(analyzer.error_message).to eq('Failed to fetch thumbnail')
      end
    end
  end
end
