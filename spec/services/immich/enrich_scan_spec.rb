# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Immich::EnrichScan do
  describe '#call' do
    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end

    let(:tolerance) { 1800 } # 30 minutes
    let(:start_date) { '2024-01-15' }
    let(:end_date) { '2024-01-16' }

    subject(:service) do
      described_class.new(user, start_date:, end_date:, tolerance:)
    end

    # Photo at 10:23 WITHOUT geodata
    let(:photo_without_geodata) do
      {
        'id' => 'asset-no-geo-1',
        'originalFileName' => 'IMG_4521.jpg',
        'localDateTime' => '2024-01-15T10:23:00.000Z',
        'exifInfo' => {
          'dateTimeOriginal' => '2024-01-15T10:23:00.000Z',
          'latitude' => nil,
          'longitude' => nil
        }
      }
    end

    # Photo at 10:45 WITHOUT geodata (zero coords)
    let(:photo_zero_coords) do
      {
        'id' => 'asset-zero-geo',
        'originalFileName' => 'IMG_4522.jpg',
        'localDateTime' => '2024-01-15T10:45:00.000Z',
        'exifInfo' => {
          'dateTimeOriginal' => '2024-01-15T10:45:00.000Z',
          'latitude' => 0,
          'longitude' => 0
        }
      }
    end

    # Photo WITH geodata (should be excluded)
    let(:photo_with_geodata) do
      {
        'id' => 'asset-with-geo',
        'originalFileName' => 'IMG_4523.jpg',
        'localDateTime' => '2024-01-15T11:00:00.000Z',
        'exifInfo' => {
          'dateTimeOriginal' => '2024-01-15T11:00:00.000Z',
          'latitude' => 52.52,
          'longitude' => 13.405
        }
      }
    end

    let(:immich_response_body) do
      {
        'assets' => {
          'total' => 3,
          'count' => 3,
          'items' => [photo_without_geodata, photo_zero_coords, photo_with_geodata]
        }
      }.to_json
    end

    let(:empty_page_body) do
      { 'assets' => { 'total' => 0, 'count' => 0, 'items' => [] } }.to_json
    end

    before do
      stub_request(:post, 'http://immich.app/api/search/metadata')
        .to_return(
          { status: 200, body: immich_response_body, headers: { 'content-type' => 'application/json' } },
          { status: 200, body: empty_page_body, headers: { 'content-type' => 'application/json' } }
        )
    end

    context 'when photos without geodata match Dawarich points' do
      let!(:point_before) do
        create(:point, user:,
               latitude: 52.50, longitude: 13.40,
               lonlat: 'POINT(13.40 52.50)',
               timestamp: Time.utc(2024, 1, 15, 10, 20).to_i) # 10:20
      end

      let!(:point_after) do
        create(:point, user:,
               latitude: 52.54, longitude: 13.41,
               lonlat: 'POINT(13.41 52.54)',
               timestamp: Time.utc(2024, 1, 15, 10, 26).to_i) # 10:26
      end

      let!(:point_near_second) do
        create(:point, user:,
               latitude: 52.53, longitude: 13.42,
               lonlat: 'POINT(13.42 52.53)',
               timestamp: Time.utc(2024, 1, 15, 10, 44).to_i) # 10:44
      end

      it 'returns matches only for photos without geodata' do
        result = service.call
        asset_ids = result[:matches].map { |m| m[:immich_asset_id] }

        expect(asset_ids).to include('asset-no-geo-1', 'asset-zero-geo')
        expect(asset_ids).not_to include('asset-with-geo')
      end

      it 'returns total counts' do
        result = service.call

        expect(result[:total_without_geodata]).to eq(2)
        expect(result[:total_matched]).to eq(2)
      end

      it 'interpolates coordinates for first photo (bracketed by two points)' do
        result = service.call
        match = result[:matches].find { |m| m[:immich_asset_id] == 'asset-no-geo-1' }

        # Photo at 10:23, points at 10:20 and 10:26
        # fraction = 3/6 = 0.5
        # lat = 52.50 + (52.54 - 52.50) * 0.5 = 52.52
        # lon = 13.40 + (13.41 - 13.40) * 0.5 = 13.405
        expect(match[:latitude]).to be_within(0.01).of(52.52)
        expect(match[:longitude]).to be_within(0.01).of(13.405)
        expect(match[:match_method]).to eq('interpolated')
      end

      it 'uses nearest point for second photo (only one nearby)' do
        result = service.call
        match = result[:matches].find { |m| m[:immich_asset_id] == 'asset-zero-geo' }

        expect(match[:latitude]).to be_within(0.01).of(52.53)
        expect(match[:longitude]).to be_within(0.01).of(13.42)
        expect(match[:match_method]).to eq('nearest')
      end

      it 'includes metadata in each match' do
        result = service.call
        match = result[:matches].first

        expect(match).to include(
          :immich_asset_id, :filename, :photo_timestamp,
          :latitude, :longitude, :time_delta_seconds, :match_method
        )
      end
    end

    context 'when no Dawarich points exist in the time range' do
      it 'returns zero matches' do
        result = service.call

        expect(result[:total_without_geodata]).to eq(2)
        expect(result[:total_matched]).to eq(0)
        expect(result[:matches]).to be_empty
      end
    end

    context 'when points exist but outside tolerance' do
      let!(:distant_point) do
        create(:point, user:,
               latitude: 52.50, longitude: 13.40,
               lonlat: 'POINT(13.40 52.50)',
               timestamp: Time.utc(2024, 1, 15, 8, 0).to_i) # 08:00 - >2hr before photos
      end

      it 'does not match distant points' do
        result = service.call

        expect(result[:total_matched]).to eq(0)
      end
    end

    context 'when Immich returns no photos' do
      let(:immich_response_body) do
        { 'assets' => { 'total' => 0, 'count' => 0, 'items' => [] } }.to_json
      end

      it 'returns empty result' do
        result = service.call

        expect(result[:total_without_geodata]).to eq(0)
        expect(result[:total_matched]).to eq(0)
        expect(result[:matches]).to be_empty
      end
    end

    context 'when Immich API fails' do
      before do
        stub_request(:post, 'http://immich.app/api/search/metadata')
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'returns error result' do
        result = service.call

        expect(result[:error]).to be_present
      end
    end

    context 'when Immich credentials are missing' do
      let(:user) { create(:user, settings: {}) }

      it 'returns error result' do
        result = service.call

        expect(result[:error]).to be_present
      end
    end
  end
end
