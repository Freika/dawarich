# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::PhotoSerializer do
  describe '#call' do
    subject(:serialized_photo) { described_class.new(photo, source).call }

    context 'when photo is from immich' do
      let(:source) { 'immich' }
      let(:photo) do
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
      end

      it 'serializes the photo correctly' do
        expect(serialized_photo).to eq(
          id: '7fe486e3-c3ba-4b54-bbf9-1281b39ed15c',
          latitude: 52.11,
          longitude: 13.22,
          localDateTime: '2023-06-08T09:58:45.637Z',
          originalFileName: 'IMG_9913.jpeg',
          city: 'Johannisthal',
          state: 'Berlin',
          country: 'Germany',
          type: 'image',
          orientation: 'portrait',
          source: 'immich'
        )
      end
    end

    context 'when photo is from photoprism' do
      let(:source) { 'photoprism' }
      let(:photo) do
        {
          'ID' => '102',
          'UID' => 'psnver0s3x7wxfnh',
          'Type' => 'image',
          'TypeSrc' => '',
          'TakenAt' => '2023-10-10T16:04:33Z',
          'TakenAtLocal' => '2023-10-10T16:04:33Z',
          'TakenSrc' => 'name',
          'TimeZone' => '',
          'Path' => '2023/10',
          'Name' => '20231010_160433_91981432',
          'OriginalName' => 'photo_2023-10-10 16.04.33',
          'Title' => 'Photo / 2023',
          'Description' => '',
          'Year' => 2023,
          'Month' => 10,
          'Day' => 10,
          'Country' => 'zz',
          'Stack' => 0,
          'Favorite' => false,
          'Private' => false,
          'Iso' => 0,
          'FocalLength' => 0,
          'FNumber' => 0,
          'Exposure' => '',
          'Quality' => 1,
          'Resolution' => 1,
          'Color' => 4,
          'Scan' => false,
          'Panorama' => false,
          'CameraID' => 1,
          'CameraModel' => 'Unknown',
          'LensID' => 1,
          'LensModel' => 'Unknown',
          'Lat' => 11,
          'Lng' => 22,
          'CellID' => 'zz',
          'PlaceID' => 'zz',
          'PlaceSrc' => '',
          'PlaceLabel' => 'Unknown',
          'PlaceCity' => 'Unknown',
          'PlaceState' => 'Unknown',
          'PlaceCountry' => 'zz',
          'InstanceID' => '',
          'FileUID' => 'fsnver0clrfzatmz',
          'FileRoot' => '/',
          'FileName' => '2023/10/20231010_160433_91981432.jpeg',
          'Hash' => 'ce1849fd7cf6a50eb201fbb669ab78c7ac13263b',
          'Width' => 1280,
          'Height' => 908,
          'Portrait' => false,
          'Merged' => false,
          'CreatedAt' => '2024-12-02T14:25:48Z',
          'UpdatedAt' => '2024-12-02T14:36:45Z',
          'EditedAt' => '0001-01-01T00:00:00Z',
          'CheckedAt' => '2024-12-02T14:36:45Z',
          'Files' => nil
        }
      end

      it 'serializes the photo correctly' do
        expect(serialized_photo).to eq(
          id: 'ce1849fd7cf6a50eb201fbb669ab78c7ac13263b',
          latitude: 11,
          longitude: 22,
          localDateTime: '2023-10-10T16:04:33Z',
          originalFileName: 'photo_2023-10-10 16.04.33',
          city: 'Unknown',
          state: 'Unknown',
          country: 'zz',
          type: 'image',
          orientation: 'landscape',
          source: 'photoprism'
        )
      end
    end
  end
end
