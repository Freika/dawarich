# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photos::Thumbnail do
  let(:user) { create(:user) }
  let(:id) { 'photo123' }

  describe '#call' do
    subject { described_class.new(user, source, id).call }

    context 'with immich source' do
      let(:source) { 'immich' }
      let(:api_key) { 'immich_key_123' }
      let(:base_url) { 'https://photos.example.com' }
      let(:expected_url) { "#{base_url}/api/assets/#{id}/thumbnail?size=preview" }
      let(:expected_headers) do
        {
          'accept' => 'application/octet-stream',
          'X-Api-Key' => api_key
        }
      end

      before do
        allow(user).to receive(:settings).and_return(
          'immich_url' => base_url,
          'immich_api_key' => api_key
        )
      end

      it 'fetches thumbnail with correct parameters' do
        expect(HTTParty).to receive(:get)
          .with(expected_url, headers: expected_headers)
          .and_return('thumbnail_data')

        expect(subject).to eq('thumbnail_data')
      end
    end

    context 'with photoprism source' do
      let(:source) { 'photoprism' }
      let(:base_url) { 'https://photoprism.example.com' }
      let(:preview_token) { 'preview_token_123' }
      let(:expected_url) { "#{base_url}/api/v1/t/#{id}/#{preview_token}/tile_500" }
      let(:expected_headers) do
        {
          'accept' => 'application/octet-stream'
        }
      end

      before do
        allow(user).to receive(:settings).and_return(
          'photoprism_url' => base_url
        )
        allow(Rails.cache).to receive(:read)
          .with("#{Photoprism::CachePreviewToken::TOKEN_CACHE_KEY}_#{user.id}")
          .and_return(preview_token)
      end

      it 'fetches thumbnail with correct parameters' do
        expect(HTTParty).to receive(:get)
          .with(expected_url, headers: expected_headers)
          .and_return('thumbnail_data')

        expect(subject).to eq('thumbnail_data')
      end
    end

    context 'with unsupported source' do
      let(:source) { 'unsupported' }

      it 'raises an error' do
        expect { subject }.to raise_error(ArgumentError, 'Unsupported source: unsupported')
      end
    end
  end
end
