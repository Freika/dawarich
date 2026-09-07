# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'Gpx::TrackImporter recoverable SAX error handling' do
  let(:user) { create(:user) }

  let(:recoverable_gpx_path) do
    f = Tempfile.new(['recoverable-import-', '.gpx'])
    f.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
        <trk><name>Recoverable</name><trkseg>
          <trkpt lat="52.5" lon="13.4">
            <ele>34.0</ele>
            <time>2026-01-01T00:00:00Z</time>
            <extensions><foo:bar>whatever</foo:bar></extensions>
          </trkpt>
          <trkpt lat="52.6" lon="13.5">
            <ele>35.0</ele>
            <time>2026-01-01T00:01:00Z</time>
          </trkpt>
        </trkseg></trk>
      </gpx>
    XML
    f.close
    f.path
  end

  let(:gpx_file) { Rack::Test::UploadedFile.new(recoverable_gpx_path, 'application/xml') }
  let(:import) { create(:import, user:, name: 'recoverable.gpx', source: 'gpx') }

  before { import.file.attach(gpx_file) }
  after  { FileUtils.rm_f(recoverable_gpx_path) }

  it 'imports the valid <trkpt> records despite the recoverable namespace error' do
    expect { Gpx::TrackImporter.new(import, user.id).call }
      .to change { Point.count }.by(2)
  end

  it 'does not raise a Nokogiri::XML::SyntaxError' do
    expect { Gpx::TrackImporter.new(import, user.id).call }
      .not_to raise_error
  end

  it 'stores the parsed points with the expected coordinates and timestamps' do
    Gpx::TrackImporter.new(import, user.id).call

    points = user.points.order(:timestamp).to_a
    expect(points.map(&:lat)).to contain_exactly(52.5, 52.6)
    expect(points.map(&:lon)).to contain_exactly(13.4, 13.5)
    expect(points.map(&:timestamp))
      .to eq([Time.zone.parse('2026-01-01T00:00:00Z').to_i,
              Time.zone.parse('2026-01-01T00:01:00Z').to_i])
  end

  it 'records the seen-trackpoint count in import raw_data' do
    Gpx::TrackImporter.new(import, user.id).call

    expect(import.reload.raw_data).to include('trackpoints_seen' => 2)
  end

  it 'leaves the import in a non-failed state so Imports::Create can complete it' do
    Imports::Create.new(user, import).call

    expect(import.reload.status).to eq('completed')
    expect(import.reload.error_message).to be_nil
  end

  context 'when every <trkpt> declares an undeclared namespace prefix' do
    let(:recoverable_gpx_path) do
      f = Tempfile.new(['recoverable-multi-', '.gpx'])
      f.write(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>RecoverableMulti</name><trkseg>
            <trkpt lat="52.5" lon="13.4">
              <ele>34.0</ele>
              <time>2026-01-01T00:00:00Z</time>
              <extensions><foo:bar>whatever</foo:bar></extensions>
            </trkpt>
            <trkpt lat="52.6" lon="13.5">
              <ele>35.0</ele>
              <time>2026-01-01T00:01:00Z</time>
              <extensions><baz:qux>whatever</baz:qux></extensions>
            </trkpt>
          </trkseg></trk>
        </gpx>
      XML
      f.close
      f.path
    end
    let(:gpx_file) { Rack::Test::UploadedFile.new(recoverable_gpx_path, 'application/xml') }

    it 'imports every point despite multiple recoverable namespace errors' do
      expect { Gpx::TrackImporter.new(import, user.id).call }
        .to change { Point.count }.by(2)
    end
  end

  context 'when a fatal (truncation) error coexists with a recoverable namespace error' do
    let(:mixed_fatal_gpx_path) do
      f = Tempfile.new(['mixed-fatal-', '.gpx'])
      f.write(<<~XML)
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>Mixed</name><trkseg>
            <trkpt lat="52.5" lon="13.4">
              <ele>34.0</ele>
              <time>2026-01-01T00:00:00Z</time>
              <extensions><foo:bar>whatever</foo:bar></extensions>
            </trkpt>
            <trkpt lat="52.6" lon="13.5"><time>2026-01-01T00:01:00Z
      XML
      f.close
      f.path
    end
    let(:gpx_file) { Rack::Test::UploadedFile.new(mixed_fatal_gpx_path, 'application/xml') }

    before { import.file.attach(gpx_file) }
    after  { FileUtils.rm_f(mixed_fatal_gpx_path) }

    it 'still raises Nokogiri::XML::SyntaxError because the truncation is fatal' do
      expect { Gpx::TrackImporter.new(import, user.id).call }
        .to raise_error(Nokogiri::XML::SyntaxError, /GPX parse error/)
    end
  end
end
