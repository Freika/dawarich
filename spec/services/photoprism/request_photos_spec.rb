# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Photoprism::RequestPhotos do
  let(:user) do
    create(
      :user,
      settings: {
        'photoprism_url' => 'http://photoprism.local',
        'photoprism_api_key' => 'test_api_key'
      }
    )
  end

  let(:start_date) { '2024-01-01' }
  let(:end_date) { '2024-12-31' }
  let(:service) { described_class.new(user, start_date: start_date, end_date: end_date) }

  let(:mock_photo_response) do
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
    ]
  end

  describe '#call' do
    context 'with valid credentials' do
      before do
        stub_request(
          :any,
          "#{user.settings['photoprism_url']}/api/v1/photos?after=#{start_date}&before=#{end_date}&count=1000&public=true&q=&quality=3"
        ).with(
          headers: {
            'Accept' => 'application/json',
            'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
            'Authorization' => 'Bearer test_api_key',
            'User-Agent' => 'Ruby'
          }
        ).to_return(
          status: 200,
          body: mock_photo_response.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

        stub_request(
          :any,
          "#{user.settings['photoprism_url']}/api/v1/photos?after=#{start_date}&before=#{end_date}&count=1000&public=true&q=&quality=3&offset=1000"
        ).to_return(status: 200, body: [].to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns photos within the specified date range' do
        result = service.call

        expect(result).to be_an(Array)
        expect(result.first['Title']).to eq('Moment / Karlovy Vary / 2024')
      end
    end

    context 'with missing credentials' do
      let(:user) { create(:user, settings: {}) }

      it 'raises error when Photoprism URL is missing' do
        expect { service.call }.to raise_error(ArgumentError, 'Photoprism URL is missing')
      end

      it 'raises error when API key is missing' do
        user.update(settings: { 'photoprism_url' => 'http://photoprism.local' })

        expect { service.call }.to raise_error(ArgumentError, 'Photoprism API key is missing')
      end
    end

    context 'when API returns an error' do
      before do
        stub_request(
          :get,
          "#{user.settings['photoprism_url']}/api/v1/photos?after=#{start_date}&before=#{end_date}&count=1000&public=true&q=&quality=3"
        ).to_return(status: 400, body: { status: 400, error: 'Unable to do that' }.to_json)
      end

      it 'logs the error' do
        expect(Rails.logger).to receive(:error).with('Photoprism photo fetch failed: Request failed: 400')
        expect(Rails.logger).to receive(:debug).with(
          "Photoprism API request params: #{{ q: '', public: true, quality: 3, after: start_date, count: 1000,
before: end_date }}"
        )

        service.call
      end
    end

    context 'with pagination' do
      let(:first_page) { [{ 'TakenAtLocal' => "#{start_date}T14:30:00Z" }] }
      let(:second_page) { [{ 'TakenAtLocal' => "#{start_date}T14:30:00Z" }] }
      let(:empty_page) { [] }
      let(:common_headers) do
        {
          'Accept' => 'application/json',
          'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
          'Authorization' => 'Bearer test_api_key',
          'User-Agent' => 'Ruby'
        }
      end

      before do
        # First page
        stub_request(:any, "#{user.settings['photoprism_url']}/api/v1/photos")
          .with(
            headers: common_headers,
            query: {
              after: start_date,
              before: end_date,
              count: '1000',
              public: 'true',
              q: '',
              quality: '3'
            }
          )
          .to_return(status: 200, body: first_page.to_json, headers: { 'Content-Type' => 'application/json' })

        # Second page
        stub_request(:any, "#{user.settings['photoprism_url']}/api/v1/photos")
          .with(
            headers: common_headers,
            query: {
              after: start_date,
              before: end_date,
              count: '1000',
              public: 'true',
              q: '',
              quality: '3',
              offset: '1000'
            }
          )
          .to_return(status: 200, body: second_page.to_json, headers: { 'Content-Type' => 'application/json' })

        # Last page (empty)
        stub_request(:any, "#{user.settings['photoprism_url']}/api/v1/photos")
          .with(
            headers: common_headers,
            query: {
              after: start_date,
              before: end_date,
              count: '1000',
              public: 'true',
              q: '',
              quality: '3',
              offset: '2000'
            }
          )
          .to_return(status: 200, body: empty_page.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'fetches all pages until empty result' do
        result = service.call

        expect(result.size).to eq(2)
      end
    end
  end
end
