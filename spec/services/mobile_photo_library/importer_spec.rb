# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MobilePhotoLibrary::Importer do
  subject(:import_photo_library) do
    File.write(file_path, JSON.generate(payload))
    described_class.new(import, user.id, file_path).call
  end

  let(:user) { create(:user) }
  let(:import) { create(:import, user:, source: :mobile_photo_library) }
  let(:payload) { JSON.parse(file_fixture('mobile_photo_library/import.json').read) }
  let(:file_path) { Rails.root.join('tmp', "mobile_photo_library_#{SecureRandom.hex(4)}.json").to_s }

  after { File.delete(file_path) if File.exist?(file_path) }

  it 'creates sparse timeline points from the on-device photo metadata' do
    expect { import_photo_library }.to change { user.points.count }.by(2)

    point = user.points.order(:timestamp).first
    expect(point.lat).to eq(48.12345)
    expect(point.lon).to eq(11.54321)
    expect(point.altitude).to eq(34.5)
    expect(point.timestamp).to eq(1_718_447_400)
    expect(point.tracker_id).to eq('mobile-photo-library')
    expect(point.topic).to eq('On-device photo library')
    expect(point.import_id).to eq(import.id)
  end

  it 'skips invalid and Null Island coordinates' do
    payload['points'] = [
      { 'timestamp' => 1_718_447_400, 'latitude' => 0, 'longitude' => 0 },
      { 'timestamp' => 1_718_447_401, 'latitude' => 91, 'longitude' => 10 },
      { 'timestamp' => nil, 'latitude' => 48, 'longitude' => 11 }
    ]

    expect { import_photo_library }.not_to change(Point, :count)
  end

  it 'rejects out-of-range coordinates before they reach the database' do
    # The shared bulk insert would also drop this, but by swallowing a PostGIS
    # error — a plain count assertion passes with the importer's filter deleted.
    payload['points'] = [{ 'timestamp' => 1_718_447_401, 'latitude' => 91, 'longitude' => 10 }]
    allow(Point).to receive(:upsert_all).and_call_original

    import_photo_library

    expect(Point).not_to have_received(:upsert_all)
  end

  it 'counts a Null Island point as rejected rather than leaving it to the bulk insert' do
    # Both layers drop (0,0); only this importer's filter attributes it to the
    # payload, so the user is told the point was unusable.
    payload['points'] = [{ 'timestamp' => 1_718_447_401, 'latitude' => 0, 'longitude' => 0 }]
    allow(Rails.logger).to receive(:info).and_call_original

    import_photo_library

    expect(Rails.logger).to have_received(:info).with(/skipped 1 points with unusable/)
  end

  it 'rejects a payload that is not an object' do
    File.write(file_path, JSON.generate([{ 'timestamp' => 1_718_447_400 }]))

    expect { described_class.new(import, user.id, file_path).call }
      .to raise_error(ArgumentError, 'Invalid Dawarich photo library import')
  end

  it 'converts millisecond timestamps to seconds' do
    payload['points'] = [{ 'timestamp' => 1_718_448_000_000, 'latitude' => 52.52, 'longitude' => 13.405 }]

    import_photo_library

    expect(user.points.first.timestamp).to eq(1_718_448_000)
  end

  it 'deduplicates points already present in the timeline' do
    existing = payload.fetch('points').first
    lonlat = "POINT(#{existing.fetch('longitude')} #{existing.fetch('latitude')})"
    create(:point, user:, timestamp: existing.fetch('timestamp'), lonlat:)

    expect { import_photo_library }.to change { user.points.count }.by(1)
    expect(import.reload.doubles).to eq(1)
  end

  it 'reports how many points it could not use' do
    payload['points'] = [
      { 'timestamp' => 1_718_447_400, 'latitude' => 48.1, 'longitude' => 11.5 },
      { 'timestamp' => '2024-06-15T10:30:00Z', 'latitude' => 48.2, 'longitude' => 11.6 },
      { 'timestamp' => 1_718_447_402, 'latitude' => nil, 'longitude' => 11.7 }
    ]
    allow(Rails.logger).to receive(:info).and_call_original

    import_photo_library

    expect(Rails.logger).to have_received(:info).with(/skipped 2 points with unusable/)
  end

  it 'imports a library larger than one batch' do
    stub_const("#{described_class}::BATCH_SIZE", 2)
    payload['points'] = Array.new(5) do |i|
      { 'timestamp' => 1_718_447_400 + i, 'latitude' => 48.1 + (i / 1000.0), 'longitude' => 11.5 }
    end

    expect { import_photo_library }.to change { user.points.count }.by(5)
  end

  it 'keeps the rest of the batch when one photo is out of range' do
    payload['points'] = [
      { 'timestamp' => 1_718_447_400, 'latitude' => 48.1, 'longitude' => 11.5 },
      # Past int4 and below the millisecond threshold, so it stays out of range.
      { 'timestamp' => 5_000_000_000, 'latitude' => 48.2, 'longitude' => 11.6 },
      { 'timestamp' => 1_718_447_402, 'latitude' => 48.3, 'longitude' => 11.7, 'altitude' => 1e12 }
    ]

    # The unusable timestamp drops its own point; the unusable altitude only
    # drops the altitude. Neither may take the rest of the batch down.
    expect { import_photo_library }.to change { user.points.count }.by(2)
    expect(user.points.find_by(timestamp: 1_718_447_402).altitude).to be_blank
  end

  it 'ignores entries that are not objects without aborting the import' do
    payload['points'] = [
      nil,
      42,
      %w[not a point],
      { 'timestamp' => 1_718_447_400, 'latitude' => 48.1, 'longitude' => 11.5 }
    ]

    expect { import_photo_library }.to change { user.points.count }.by(1)
  end

  it 'rejects an unsupported payload version' do
    payload['version'] = 2

    expect { import_photo_library }.to raise_error(ArgumentError, 'Invalid Dawarich photo library import')
  end
end
