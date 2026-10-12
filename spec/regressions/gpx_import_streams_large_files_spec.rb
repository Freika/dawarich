# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'Gpx::TrackImporter streaming behavior on large files' do
  let(:user) { create(:user) }
  let(:n_points) { 5_500 }
  let(:expected_batches) { (n_points.to_f / Gpx::TrackImporter::BATCH_SIZE).ceil }

  let(:gpx_path) do
    f = Tempfile.new(['streaming-import-', '.gpx'])
    f.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="rspec">
        <trk><name>Streaming</name><trkseg>
    XML
    base = Time.zone.parse('2026-01-01T00:00:00Z').to_i
    n_points.times do |i|
      lat = format('%.6f', 50.0 + i * 0.00001)
      lon = format('%.6f', 10.0 + i * 0.00001)
      ts  = Time.at(base + i).utc.iso8601
      f.write(%(<trkpt lat="#{lat}" lon="#{lon}"><ele>100.0</ele><time>#{ts}</time></trkpt>\n))
    end
    f.write("</trkseg></trk></gpx>\n")
    f.close
    f.path
  end

  let(:gpx_file) { Rack::Test::UploadedFile.new(gpx_path, 'application/xml') }
  let(:import) { create(:import, user:, name: 'streaming.gpx', source: 'gpx') }

  before { import.file.attach(gpx_file) }
  after  { FileUtils.rm_f(gpx_path) }

  it 'flushes points in BATCH_SIZE chunks instead of materializing the whole file' do
    expect_any_instance_of(Imports::Broadcaster)
      .to receive(:broadcast_import_progress)
      .exactly(expected_batches).times

    expect { Gpx::TrackImporter.new(import, user.id).call }
      .to change { user.points.count }.by(n_points)
  end
end
