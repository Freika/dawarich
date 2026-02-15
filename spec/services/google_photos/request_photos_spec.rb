# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GooglePhotos::RequestPhotos do
  describe '#call' do
    subject(:service) { described_class.new(user, start_date: start_date, end_date: end_date) }

    let(:user) do
      create(:user, settings: {
               'google_photos_access_token' => 'access_token_123',
               'google_photos_refresh_token' => 'refresh_token_123',
               'google_photos_token_expires_at' => 1.hour.from_now.to_i
             })
    end
    let(:start_date) { '2023-01-01' }
    let(:end_date) { '2023-12-31' }

    let(:mock_google_photos_response) do
      {
        mediaItems: [
          {
            id: 'photo_id_1',
            baseUrl: 'https://lh3.googleusercontent.com/photo1',
            filename: 'IMG_001.jpg',
            mediaMetadata: {
              creationTime: '2023-06-15T10:30:00Z',
              width: '4000',
              height: '3000',
              photo: {
                cameraMake: 'Apple',
                cameraModel: 'iPhone 12 Pro'
              },
              location: {
                latitude: 52.5200,
                longitude: 13.4050
              }
            }
          },
          {
            id: 'photo_id_2',
            baseUrl: 'https://lh3.googleusercontent.com/photo2',
            filename: 'IMG_002.jpg',
            mediaMetadata: {
              creationTime: '2023-07-20T14:45:00Z',
              width: '3000',
              height: '4000',
              photo: {
                cameraMake: 'Samsung',
                cameraModel: 'Galaxy S21'
              }
            }
          }
        ]
      }.to_json
    end

    before do
      allow(DawarichSettings).to receive(:google_photos_available?).and_return(true)
    end

    context 'when user has valid Google Photos tokens' do
      before do
        stub_request(:post, 'https://photoslibrary.googleapis.com/v1/mediaItems:search')
          .to_return(
            status: 200,
            body: mock_google_photos_response,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns photos from Google Photos API' do
        result = service.call

        expect(result).to be_an(Array)
        expect(result.length).to eq(2)
      end

      it 'includes photo metadata' do
        result = service.call

        photo = result.first
        expect(photo['id']).to eq('photo_id_1')
        expect(photo['baseUrl']).to eq('https://lh3.googleusercontent.com/photo1')
        expect(photo['filename']).to eq('IMG_001.jpg')
      end
    end

    context 'when token refresh fails' do
      let(:user) do
        create(:user, settings: {
                 'google_photos_access_token' => 'expired_token',
                 'google_photos_refresh_token' => 'invalid_refresh_token',
                 'google_photos_token_expires_at' => 1.hour.ago.to_i
               })
      end

      before do
        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .to_return(status: 400, body: '{"error": "invalid_grant"}')
      end

      it 'returns nil' do
        result = service.call

        expect(result).to be_nil
      end
    end

    context 'when API request fails' do
      before do
        stub_request(:post, 'https://photoslibrary.googleapis.com/v1/mediaItems:search')
          .to_return(status: 500, body: '{"error": "Internal Server Error"}')
      end

      it 'returns nil' do
        result = service.call

        expect(result).to be_nil
      end
    end

    context 'when no tokens are configured' do
      let(:user) { create(:user, settings: {}) }

      it 'returns nil' do
        result = service.call

        expect(result).to be_nil
      end
    end
  end
end
