# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Streaming JSON imports' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user) }
  let(:path) { Rails.root.join('tmp', "stream-#{SecureRandom.hex(6)}.json").to_s }

  after { File.delete(path) if File.exist?(path) }

  def without_whole_document(strict: true)
    expect(Oj).not_to receive(:load)
    expect(Oj).not_to receive(:saj_parse) if strict
    expect(File).not_to receive(:read).with(path)
    yield
  end

  it 'streams Records in bounded batches with identical point fields and progress offsets' do
    locations = Array.new(2003) do |i|
      {
        'latitudeE7' => 513_402_000 + i, 'longitudeE7' => 123_712_000,
        'timestampMs' => (1_700_000_000_000 + i * 1000).to_s,
        'deviceTag' => 17, 'altitude' => 23, 'accuracy' => 10, 'velocity' => 2,
        'verticalAccuracy' => 4, 'heading' => 90, 'batteryCharging' => true,
        'activity' => [{ 'timestamp' => '2020-01-01T00:00:00Z',
                         'activity' => [{ 'type' => 'WALKING', 'confidence' => 80 }] }]
      }
    end
    File.write(path, JSON.generate('locations' => locations, 'ignored' => { 'locations' => locations.first(2) }))
    GoogleMaps::RecordsImporter.new(import).call(locations)
    columns = Point.column_names - %w[id created_at updated_at]
    expected = user.points.order(:timestamp).map { |point| point.attributes.slice(*columns) }
    user.points.delete_all
    offsets = []
    allow_any_instance_of(GoogleMaps::RecordsImporter).to receive(:broadcast_import_progress) do |_, _, index|
      offsets << index
    end

    without_whole_document { GoogleMaps::RecordsStorageImporter.new(import, user.id, path).call }

    expect(user.points.count).to eq(2003)
    expect(user.points.order(:timestamp).map { |point| point.attributes.slice(*columns) }).to eq(expected)
    expect(offsets).to eq([0, 1000, 2000])
  end

  it 'streams attached Records while scrubbing invalid UTF-8 and rejecting malformed tails before inserts' do
    content = '{"locations":[{"latitudeE7":513402000,"longitudeE7":123712000,' \
              '"timestamp":"2024-01-01T00:00:00Z","deviceTag":"phoneBYTE"}]}'
    content = content.b.sub('BYTE', "\xFF".b)
    import.file.attach(io: StringIO.new(content), filename: 'records.json', content_type: 'application/json')
    without_whole_document(strict: false) { GoogleMaps::RecordsStorageImporter.new(import, user.id).call }
    expect(user.points.sole.tracker_id).to eq("google-records-device-phone\uFFFD")
    File.binwrite(path, content.sub(/\]\}\z/, '],'))
    expect { GoogleMaps::RecordsStorageImporter.new(import, user.id, path).call }.to raise_error(JSON::ParserError)
    expect(user.points.count).to eq(1)
  end

  it 'streams Polarsteps trails and keeps valid-point batching and progress' do
    locations = Array.new(1002) { |i| { lat: 51.3, lon: 12.3, time: 1_700_000_000 + i } }
    File.write(path, JSON.generate(locations: [nil, *locations]))
    without_whole_document { Polarsteps::Importer.new(import, user.id, path).call }
    expect(user.points.order(:timestamp).pluck(:timestamp)).to eq(locations.map { |point| point[:time] })
  end

  it 'streams complete photo API libraries without retaining the document' do
    points = Array.new(1002) do |i|
      { latitude: 51.3, longitude: 12.3, lonlat: 'POINT(12.3 51.3)', timestamp: 1_700_000_000 + i }
    end
    File.write(path, JSON.generate(points))
    without_whole_document { Photos::Importer.new(import, user.id, path).call }
    expect(user.points.order(:timestamp).pluck(:timestamp)).to eq(points.map { |point| point[:timestamp] })
  end

  it 'streams mobile photo libraries with metadata after points and validates before inserting' do
    points = Array.new(1002) { |i| { latitude: 51.3, longitude: 12.3, timestamp: 1_700_000_000 + i } }
    File.write(path, JSON.generate(points: points, version: 1, type: 'DawarichPhotoLibrary'))
    without_whole_document { MobilePhotoLibrary::Importer.new(import, user.id, path).call }
    expect(user.points.order(:timestamp).pluck(:timestamp)).to eq(points.map { |point| point[:timestamp] })
    File.write(path, JSON.generate(points: points, version: 2, type: 'DawarichPhotoLibrary'))
    expect { MobilePhotoLibrary::Importer.new(import, user.id, path).call }.to raise_error(ArgumentError)
  end

  it 'streams Polarsteps enhanced visits while ignoring the GPS trail' do
    steps = Array.new(1002) do |i|
      { id: i, lat: 51.3, lon: 12.3, arrived: 1_700_000_000 + i * 3600,
        departed: 1_700_000_600 + i * 3600, name: "Stop #{i}" }
    end
    File.write(path, JSON.generate(steps: steps, locations: steps))
    visits = nil
    without_whole_document { visits = EnhancedImport::Adapters::PolarstepsAdapter.new(import, path).translate.to_a }
    expect(visits.map(&:name)).to eq(steps.map { |step| step[:name] })
  end
end
