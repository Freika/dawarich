# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::RequestPhotos do
  describe '#call' do
    subject(:service) { described_class.new(user).call }

    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end
    let(:immich_data) do
      {
        "albums": {
          "total": 0,
          "count": 0,
          "items": [],
          "facets": []
        },
        "assets": {
          "total": 1000,
          "count": 1000,
          "items": [
            {
              "id": '7fe486e3-c3ba-4b54-bbf9-1281b39ed15c',
              "deviceAssetId": 'IMG_9913.jpeg-1168914',
              "ownerId": 'f579f328-c355-438c-a82c-fe3390bd5f08',
              "deviceId": 'CLI',
              "libraryId": nil,
              "type": 'IMAGE',
              "originalPath": 'upload/library/admin/2023/2023-06-08/IMG_9913.jpeg',
              "originalFileName": 'IMG_9913.jpeg',
              "originalMimeType": 'image/jpeg',
              "thumbhash": '4RgONQaZqYaH93g3h3p3d6RfPPrG',
              "fileCreatedAt": '2023-06-08T07:58:45.637Z',
              "fileModifiedAt": '2023-06-08T09:58:45.000Z',
              "localDateTime": '2023-06-08T09:58:45.637Z',
              "updatedAt": '2024-08-24T18:20:47.965Z',
              "isFavorite": false,
              "isArchived": false,
              "isTrashed": false,
              "duration": '0:00:00.00000',
              "exifInfo": {
                "make": 'Apple',
                "model": 'iPhone 12 Pro',
                "exifImageWidth": 4032,
                "exifImageHeight": 3024,
                "fileSizeInByte": 1_168_914,
                "orientation": '6',
                "dateTimeOriginal": '2023-06-08T07:58:45.637Z',
                "modifyDate": '2023-06-08T07:58:45.000Z',
                "timeZone": 'Europe/Berlin',
                "lensModel": 'iPhone 12 Pro back triple camera 4.2mm f/1.6',
                "fNumber": 1.6,
                "focalLength": 4.2,
                "iso": 320,
                "exposureTime": '1/60',
                "latitude": 52.11,
                "longitude": 13.22,
                "city": 'Johannisthal',
                "state": 'Berlin',
                "country": 'Germany',
                "description": '',
                "projectionType": nil,
                "rating": nil
              },
              "livePhotoVideoId": nil,
              "people": [],
              "checksum": 'aL1edPVg4ZpEnS6xCRWNUY0pUS8=',
              "isOffline": false,
              "hasMetadata": true,
              "duplicateId": '88a34bee-783d-46e4-aa52-33b75ffda375',
              "resized": true
            }
          ]
        }
      }.to_json
    end

    context 'when user has immich_url and immich_api_key' do
      before do
        stub_request(
          :any,
          'http://immich.app/api/search/metadata'
        ).to_return(status: 200, body: immich_data, headers: {})
      end
    end

    context 'when user has no immich_url' do
      before do
        user.settings['immich_url'] = nil
        user.save
      end

      it 'raises ArgumentError' do
        expect { service }.to raise_error(ArgumentError, 'Immich URL is missing')
      end
    end

    context 'when user has no immich_api_key' do
      before do
        user.settings['immich_api_key'] = nil
        user.save
      end

      it 'raises ArgumentError' do
        expect { service }.to raise_error(ArgumentError, 'Immich API key is missing')
      end
    end
  end
end
