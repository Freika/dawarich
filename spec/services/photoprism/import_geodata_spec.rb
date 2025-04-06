# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photoprism::ImportGeodata do
  describe '#call' do
    subject(:service) { described_class.new(user).call }

    let(:user) do
      create(:user, settings: { 'photoprism_url' => 'http://photoprism.app', 'photoprism_api_key' => '123456' })
    end
    let(:photoprism_data) do
      [
        {
          'ID' => '82',
          'UID' => 'psnveqq089xhy1c3',
          'Type' => 'image',
          'TypeSrc' => '',
          'TakenAt' => '2024-08-18T14:11:05Z',
          'TakenAtLocal' => '2024-08-18T16:11:05Z',
          'TakenSrc' => 'meta',
          'TimeZone' => 'Europe/Prague',
          'Path' => '2024/08',
          'Name' => '20240818_141105_44E61AED',
          'OriginalName' => 'PXL_20240818_141105789',
          'Title' => 'Moment / Karlovy Vary / 2024',
          'Description' => '',
          'Year' => 2024,
          'Month' => 8,
          'Day' => 18,
          'Country' => 'cz',
          'Stack' => 0,
          'Favorite' => false,
          'Private' => false,
          'Iso' => 37,
          'FocalLength' => 21,
          'FNumber' => 2.2,
          'Exposure' => '1/347',
          'Quality' => 4,
          'Resolution' => 10,
          'Color' => 2,
          'Scan' => false,
          'Panorama' => false,
          'CameraID' => 8,
          'CameraSrc' => 'meta',
          'CameraMake' => 'Google',
          'CameraModel' => 'Pixel 7 Pro',
          'LensID' => 11,
          'LensMake' => 'Google',
          'LensModel' => 'Pixel 7 Pro front camera 2.74mm f/2.2',
          'Altitude' => 423,
          'Lat' => 50.11,
          'Lng' => 12.12,
          'CellID' => 's2:47a09944f33c',
          'PlaceID' => 'cz:ciNqTjWuq6NN',
          'PlaceSrc' => 'meta',
          'PlaceLabel' => 'Karlovy Vary, Severozápad, Czech Republic',
          'PlaceCity' => 'Karlovy Vary',
          'PlaceState' => 'Severozápad',
          'PlaceCountry' => 'cz',
          'InstanceID' => '',
          'FileUID' => 'fsnveqqeusn692qo',
          'FileRoot' => '/',
          'FileName' => '2024/08/20240818_141105_44E61AED.jpg',
          'Hash' => 'cc5d0f544e52b288d7c8460d2e1bb17fa66e6089',
          'Width' => 2736,
          'Height' => 3648,
          'Portrait' => true,
          'Merged' => false,
          'CreatedAt' => '2024-12-02T14:25:38Z',
          'UpdatedAt' => '2024-12-02T14:25:38Z',
          'EditedAt' => '0001-01-01T00:00:00Z',
          'CheckedAt' => '2024-12-02T14:36:45Z',
          'Files' => nil
        },
        {
          'ID' => '81',
          'UID' => 'psnveqpl96gcfdzf',
          'Type' => 'image',
          'TypeSrc' => '',
          'TakenAt' => '2024-08-18T14:11:04Z',
          'TakenAtLocal' => '2024-08-18T16:11:04Z',
          'TakenSrc' => 'meta',
          'TimeZone' => 'Europe/Prague',
          'Path' => '2024/08',
          'Name' => '20240818_141104_E9949CD4',
          'OriginalName' => 'PXL_20240818_141104633',
          'Title' => 'Portrait / Karlovy Vary / 2024',
          'Description' => '',
          'Year' => 2024,
          'Month' => 8,
          'Day' => 18,
          'Country' => 'cz',
          'Stack' => 0,
          'Favorite' => false,
          'Private' => false,
          'Iso' => 43,
          'FocalLength' => 21,
          'FNumber' => 2.2,
          'Exposure' => '1/356',
          'Faces' => 1,
          'Quality' => 4,
          'Resolution' => 10,
          'Color' => 2,
          'Scan' => false,
          'Panorama' => false,
          'CameraID' => 8,
          'CameraSrc' => 'meta',
          'CameraMake' => 'Google',
          'CameraModel' => 'Pixel 7 Pro',
          'LensID' => 11,
          'LensMake' => 'Google',
          'LensModel' => 'Pixel 7 Pro front camera 2.74mm f/2.2',
          'Altitude' => 423,
          'Lat' => 50.21,
          'Lng' => 12.85,
          'CellID' => 's2:47a09944f33c',
          'PlaceID' => 'cz:ciNqTjWuq6NN',
          'PlaceSrc' => 'meta',
          'PlaceLabel' => 'Karlovy Vary, Severozápad, Czech Republic',
          'PlaceCity' => 'Karlovy Vary',
          'PlaceState' => 'Severozápad',
          'PlaceCountry' => 'cz',
          'InstanceID' => '',
          'FileUID' => 'fsnveqp9xsl7onsv',
          'FileRoot' => '/',
          'FileName' => '2024/08/20240818_141104_E9949CD4.jpg',
          'Hash' => 'd5dfadc56a0b63051dfe0b5dec55ff1d81f033b7',
          'Width' => 2736,
          'Height' => 3648,
          'Portrait' => true,
          'Merged' => false,
          'CreatedAt' => '2024-12-02T14:25:37Z',
          'UpdatedAt' => '2024-12-02T14:25:37Z',
          'EditedAt' => '0001-01-01T00:00:00Z',
          'CheckedAt' => '2024-12-02T14:36:45Z',
          'Files' => nil
        }
      ].to_json
    end

    before do
      stub_request(:get, %r{http://photoprism\.app/api/v1/photos}).with(
        headers: {
          'Accept' => 'application/json',
          'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Authorization' => 'Bearer 123456',
          'User-Agent' => 'Ruby'
        }
      ).to_return(status: 200, body: photoprism_data, headers: {})
    end

    it 'creates import' do
      expect { service }.to change { Import.count }.by(1)
    end

    it 'enqueues Import::ProcessJob' do
      expect(Import::ProcessJob).to receive(:perform_later)

      service
    end

    context 'when import already exists' do
      before { service }

      it 'does not create new import' do
        expect { service }.not_to(change { Import.count })
      end

      it 'does not enqueue Import::ProcessJob' do
        expect(Import::ProcessJob).to_not receive(:perform_later)

        service
      end
    end
  end
end
