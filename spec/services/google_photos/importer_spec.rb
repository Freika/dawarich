# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GooglePhotos::Importer do
  subject(:import_sidecar) { described_class.new(import, user.id, file_path).call }

  let(:user) { create(:user) }
  let(:import) { create(:import, user:, source: :google_photos) }
  let(:sidecar) { JSON.parse(file_fixture('google_photos/sidecar.json').read) }
  let(:file_path) { Rails.root.join('tmp', "google_photos_sidecar_#{SecureRandom.hex(4)}.json").to_s }

  before { File.write(file_path, JSON.generate(sidecar)) }

  after { File.delete(file_path) if File.exist?(file_path) }

  it 'creates a sparse timeline point from EXIF geodata and the photo-taken time' do
    expect { import_sidecar }.to change { user.points.count }.by(1)

    point = user.points.last
    expect(point.lat).to eq(48.12345)
    expect(point.lon).to eq(11.54321)
    expect(point.altitude).to eq(34.5)
    expect(point.timestamp).to eq(1_718_447_400)
    expect(point.tracker_id).to eq('google-photos-takeout')
    expect(point.topic).to eq('Google Photos Takeout')
    expect(point.raw_data).to eq({})
  end

  context 'without photoTakenTime' do
    let(:sidecar) { super().except('photoTakenTime') }

    it 'falls back to the creation timestamp' do
      import_sidecar

      expect(user.points.last.timestamp).to eq(1_718_448_000)
    end
  end

  context 'with a zero photoTakenTime timestamp' do
    let(:sidecar) { super().merge('photoTakenTime' => { 'timestamp' => '0' }) }

    it 'falls back to the creation timestamp instead of dropping the point' do
      expect { import_sidecar }.to change { user.points.count }.by(1)

      expect(user.points.last.timestamp).to eq(1_718_448_000)
    end
  end

  context 'when both geoData and geoDataExif carry coordinates' do
    let(:sidecar) do
      super().merge(
        'geoData' => { 'latitude' => 40.0, 'longitude' => 5.0, 'altitude' => 0.0 },
        'geoDataExif' => { 'latitude' => 48.12345, 'longitude' => 11.54321, 'altitude' => 34.5 }
      )
    end

    it 'prefers the camera EXIF coordinates' do
      import_sidecar

      point = user.points.last
      expect(point.lat).to eq(48.12345)
      expect(point.lon).to eq(11.54321)
    end
  end

  context 'without geodata' do
    let(:sidecar) { super().except('geoDataExif') }

    it 'skips the sidecar without creating a point' do
      expect { import_sidecar }.not_to change(Point, :count)
    end
  end

  context 'with zero-coordinate placeholder geodata' do
    let(:sidecar) do
      super().merge('geoDataExif' => { 'latitude' => 0.0, 'longitude' => 0.0, 'altitude' => 0.0 })
    end

    it 'skips the sidecar without creating a Null Island point' do
      expect { import_sidecar }.not_to change(Point, :count)
    end
  end
end
