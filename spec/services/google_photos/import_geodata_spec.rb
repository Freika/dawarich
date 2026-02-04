# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GooglePhotos::ImportGeodata do
  describe '#call' do
    subject(:service) { described_class.new(user) }

    let(:user) do
      create(:user, settings: {
               'google_photos_access_token' => 'access_token_123',
               'google_photos_refresh_token' => 'refresh_token_123',
               'google_photos_token_expires_at' => 1.hour.from_now.to_i
             })
    end

    let(:mock_photos_with_location) do
      [
        {
          'id' => 'photo_id_1',
          'baseUrl' => 'https://lh3.googleusercontent.com/photo1',
          'filename' => 'IMG_001.jpg',
          'mediaMetadata' => {
            'creationTime' => '2023-06-15T10:30:00Z',
            'width' => '4000',
            'height' => '3000',
            'photo' => {},
            'location' => {
              'latitude' => 52.5200,
              'longitude' => 13.4050
            }
          }
        },
        {
          'id' => 'photo_id_2',
          'baseUrl' => 'https://lh3.googleusercontent.com/photo2',
          'filename' => 'IMG_002.jpg',
          'mediaMetadata' => {
            'creationTime' => '2023-07-20T14:45:00Z',
            'width' => '3000',
            'height' => '4000',
            'photo' => {},
            'location' => {
              'latitude' => 48.8566,
              'longitude' => 2.3522
            }
          }
        }
      ]
    end

    before do
      allow(GooglePhotos::RequestPhotos).to receive(:new).and_return(
        instance_double(GooglePhotos::RequestPhotos, call: mock_photos_with_location)
      )
    end

    context 'when photos have location data' do
      it 'creates an import' do
        expect { service.call }.to change(Import, :count).by(1)
      end

      it 'creates import with google_photos_api source' do
        service.call

        import = Import.last
        expect(import.source).to eq('google_photos_api')
      end

      it 'attaches geodata file' do
        service.call

        import = Import.last
        expect(import.file).to be_attached
      end

      it 'extracts correct geodata format' do
        service.call

        import = Import.last
        geodata = JSON.parse(import.file.download)

        expect(geodata.length).to eq(2)
        expect(geodata.first['latitude']).to eq(52.5200)
        expect(geodata.first['longitude']).to eq(13.4050)
        expect(geodata.first['lonlat']).to eq('SRID=4326;POINT(13.405 52.52)')
      end
    end

    context 'when import with same name already exists' do
      before do
        service.call
      end

      it 'does not create duplicate import' do
        expect { service.call }.not_to change(Import, :count)
      end

      it 'creates a notification' do
        expect { service.call }.to change(Notification, :count).by(1)
      end
    end

    context 'when no photos are returned' do
      before do
        allow(GooglePhotos::RequestPhotos).to receive(:new).and_return(
          instance_double(GooglePhotos::RequestPhotos, call: nil)
        )
      end

      it 'does not create an import' do
        expect { service.call }.not_to change(Import, :count)
      end
    end

    context 'when photos have no location data' do
      let(:photos_without_location) do
        [
          {
            'id' => 'photo_id_1',
            'baseUrl' => 'https://lh3.googleusercontent.com/photo1',
            'filename' => 'IMG_001.jpg',
            'mediaMetadata' => {
              'creationTime' => '2023-06-15T10:30:00Z',
              'width' => '4000',
              'height' => '3000',
              'photo' => {}
            }
          }
        ]
      end

      before do
        allow(GooglePhotos::RequestPhotos).to receive(:new).and_return(
          instance_double(GooglePhotos::RequestPhotos, call: photos_without_location)
        )
      end

      it 'does not create an import' do
        expect { service.call }.not_to change(Import, :count)
      end
    end
  end
end
