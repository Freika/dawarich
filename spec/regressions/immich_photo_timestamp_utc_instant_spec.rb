# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Immich photo timestamps render as canonical UTC instants regardless of host TZ' do
  let(:utc_instant_iso) { '2026-01-14T23:01:32.000Z' }
  let(:utc_instant_unix) { Time.iso8601(utc_instant_iso).utc.to_i }

  let(:asset_attrs) do
    {
      "id": 'asset-12345',
      "type": 'IMAGE',
      "originalFileName": 'IMG_0001.jpg',
      "fileCreatedAt": utc_instant_iso,
      "localDateTime": '2026-01-15T08:01:32.000',
      "exifInfo": {
        "dateTimeOriginal": '2026-01-15T08:01:32.000',
        "latitude": 35.6762,
        "longitude": 139.6503,
        "orientation": '1',
        "timeZone": 'Asia/Tokyo'
      }
    }
  end

  let(:asset_hash) { JSON.parse(asset_attrs.to_json) }

  describe Api::PhotoSerializer do
    it 'emits the UTC instant for an Immich asset on the capturedAt field' do
      result = described_class.new(asset_hash, 'immich').call

      expect(result[:capturedAt]).to eq(utc_instant_iso)
      expect(result[:localDateTime]).to eq('2026-01-15T08:01:32.000')
    end
  end

  describe Immich::RequestPhotos do
    let(:user) do
      create(:user, settings: { 'immich_url' => 'http://immich.app', 'immich_api_key' => '123456' })
    end

    let(:populated_response) do
      {
        "albums": { "total": 0, "count": 0, "items": [], "facets": [] },
        "assets": { "total": 1, "count": 1, "items": [asset_attrs], "nextPage": nil }
      }.to_json
    end

    let(:empty_response) do
      {
        "albums": { "total": 0, "count": 0, "items": [], "facets": [] },
        "assets": { "total": 0, "count": 0, "items": [], "nextPage": nil }
      }.to_json
    end

    before do
      stub_request(:any, 'http://immich.app/api/search/metadata')
        .to_return({ status: 200, body: populated_response, headers: { 'content-type' => 'application/json' } })
        .then.to_return({ status: 200, body: empty_response, headers: { 'content-type' => 'application/json' } })
    end

    it 'includes the asset when its UTC date matches the requested day' do
      service = described_class.new(
        user,
        start_date: '2026-01-14T00:00:00Z',
        end_date: '2026-01-15T00:00:00Z'
      )

      expect(service.call.map { _1['id'] }).to include('asset-12345')
    end

    it 'excludes the asset when only its wall-clock-local date matches but UTC date does not' do
      service = described_class.new(
        user,
        start_date: '2026-01-15T00:00:00Z',
        end_date: '2026-01-16T00:00:00Z'
      )

      expect(service.call).to be_empty
    end
  end
end
