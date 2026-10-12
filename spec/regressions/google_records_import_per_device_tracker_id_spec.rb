# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Google records.json import scopes tracker_id by device_tag' do
  subject(:run_import) { GoogleMaps::RecordsImporter.new(import).call(locations) }

  let(:import) { create(:import) }
  let(:base_time) { DateTime.new(2025, 6, 1, 12, 0, 0) }

  let(:locations) do
    [
      build_location('A', device_tag: 1_111_111_111, lat: 52.52,  lon: 13.405,  offset: 0),
      build_location('B', device_tag: 1_111_111_111, lat: 52.521, lon: 13.406,  offset: 60),
      build_location('C', device_tag: 2_222_222_222, lat: 48.8566, lon: 2.3522, offset: 30),
      build_location('D', device_tag: 2_222_222_222, lat: 48.8576, lon: 2.3532, offset: 90),
      build_location('E', device_tag: nil,           lat: 51.5074, lon: -0.1278, offset: 120)
    ]
  end

  it 'tags points from distinct device_tags with distinct tracker_ids' do
    run_import

    tracker_ids = Point.where(import_id: import.id).pluck(:tracker_id).uniq
    expect(tracker_ids).to contain_exactly(
      'google-records-device-1111111111',
      'google-records-device-2222222222',
      "google-records-#{import.id}"
    )
  end

  it 'falls back to the per-import tracker_id when device_tag is missing' do
    run_import

    fallback_count = Point.where(import_id: import.id, tracker_id: "google-records-#{import.id}").count
    expect(fallback_count).to eq(1)
  end

  def build_location(_label, device_tag:, lat:, lon:, offset:)
    ts_ms = ((base_time + offset.seconds).to_f * 1000).to_i
    {
      'timestampMs' => ts_ms.to_s,
      'latitudeE7' => (lat * 10**7).to_i,
      'longitudeE7' => (lon * 10**7).to_i,
      'accuracy' => 10,
      'altitude' => 50,
      'velocity' => 1,
      'deviceTag' => device_tag
    }
  end
end
