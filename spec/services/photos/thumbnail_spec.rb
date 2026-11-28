# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photos::Thumbnail do
  subject(:thumbnail) { described_class.new(user, source, id).call }

  let(:id) { 'photo123' }

  context 'with immich source' do
    let(:source) { 'immich' }
    let(:user) do
      create(:user, settings: { 'immich_url' => 'https://photos.example.com', 'immich_api_key' => 'immich_key_123' })
    end

    it 'fetches the preview with the API key' do
      request = stub_request(:get, 'https://photos.example.com/api/assets/photo123/thumbnail?size=preview')
                .with(headers: { 'Accept' => 'application/octet-stream', 'X-Api-Key' => 'immich_key_123' })
                .to_return(status: 200, body: 'thumbnail_data')

      expect(thumbnail).to be_success
      expect(thumbnail.body).to eq('thumbnail_data')
      expect(request).to have_been_requested
    end

    it 'returns the upstream answer when the asset is not readable' do
      stub_request(:get, 'https://photos.example.com/api/assets/photo123/thumbnail?size=preview')
        .to_return(status: 403, body: '{}')

      expect(thumbnail).not_to be_success
      expect(thumbnail.code).to eq(403)
    end

    context 'with an id that tries to leave the asset path' do
      let(:id) { '../admin' }

      it 'escapes it' do
        request = stub_request(:get, 'https://photos.example.com/api/assets/..%2Fadmin/thumbnail?size=preview')
                  .to_return(status: 404)

        thumbnail

        expect(request).to have_been_requested
      end
    end

    it 'gives up on a server that does not answer' do
      stub_request(:get, 'https://photos.example.com/api/assets/photo123/thumbnail?size=preview').to_timeout

      expect { thumbnail }.to raise_error(Integrations::Transport::RetryableError)
    end
  end

  context 'with photoprism source' do
    let(:source) { 'photoprism' }
    let(:user) { create(:user, settings: { 'photoprism_url' => 'https://photoprism.example.com' }) }

    before do
      allow(Rails.cache).to receive(:read).and_call_original
      allow(Rails.cache).to receive(:read)
        .with("#{Photoprism::CachePreviewToken::TOKEN_CACHE_KEY}_#{user.id}").and_return('preview_token_123')
    end

    it 'fetches the tile with the cached preview token and no API key' do
      request = stub_request(:get, 'https://photoprism.example.com/api/v1/t/photo123/preview_token_123/tile_500')
                .with { |req| req.headers.keys.none? { |name| name.casecmp?('x-api-key') } }
                .to_return(status: 200, body: 'thumbnail_data')

      expect(thumbnail.body).to eq('thumbnail_data')
      expect(request).to have_been_requested
    end
  end

  context 'with unsupported source' do
    let(:source) { 'unsupported' }
    let(:user) { create(:user) }

    it 'raises an error' do
      expect { thumbnail }.to raise_error(ArgumentError, 'Unsupported source: unsupported')
    end
  end
end
