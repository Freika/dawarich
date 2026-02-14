# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GooglePhotos::ConnectionTester do
  describe '#call' do
    subject(:service) { described_class.new(user) }

    let(:user) do
      create(:user, settings: {
               'google_photos_access_token' => 'access_token_123',
               'google_photos_refresh_token' => 'refresh_token_123',
               'google_photos_token_expires_at' => 1.hour.from_now.to_i
             })
    end

    context 'when Google Photos is not configured' do
      let(:user) { create(:user, settings: {}) }

      it 'returns error' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Google Photos not configured')
      end
    end

    context 'when connection is successful' do
      before do
        stub_request(:get, 'https://photoslibrary.googleapis.com/v1/mediaItems?pageSize=1')
          .to_return(
            status: 200,
            body: '{"mediaItems": []}',
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns success' do
        result = service.call

        expect(result[:success]).to be true
        expect(result[:message]).to eq('Google Photos connection verified')
      end
    end

    context 'when API returns error' do
      before do
        stub_request(:get, 'https://photoslibrary.googleapis.com/v1/mediaItems?pageSize=1')
          .to_return(
            status: 403,
            body: '{"error": {"message": "Forbidden"}}',
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns error with message' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Forbidden')
      end
    end

    context 'when request times out' do
      before do
        stub_request(:get, 'https://photoslibrary.googleapis.com/v1/mediaItems?pageSize=1')
          .to_timeout
      end

      it 'returns connection error' do
        result = service.call

        expect(result[:success]).to be false
        expect(result[:error]).to include('Connection failed')
      end
    end
  end
end
