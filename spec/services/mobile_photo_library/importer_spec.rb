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

  it 'deduplicates points already present in the timeline' do
    existing = payload.fetch('points').first
    lonlat = "POINT(#{existing.fetch('longitude')} #{existing.fetch('latitude')})"
    create(:point, user:, timestamp: existing.fetch('timestamp'), lonlat:)

    expect { import_photo_library }.to change { user.points.count }.by(1)
    expect(import.reload.doubles).to eq(1)
  end

  it 'rejects an unsupported payload version' do
    payload['version'] = 2

    expect { import_photo_library }.to raise_error(ArgumentError, 'Invalid Dawarich photo library import')
  end
end
