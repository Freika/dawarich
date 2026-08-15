# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'Gpx::TrackImporter malformed XML handling' do
  let(:user) { create(:user) }

  let(:malformed_gpx_path) do
    f = Tempfile.new(['malformed-import-', '.gpx'])
    f.write(<<~XML)
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" creator="rspec">
        <trk><name>Truncated</name><trkseg>
          <trkpt lat="50.0" lon="10.0"><time>2026-01-01T00:00:00Z</time></trkpt>
          <trkpt lat="50.0001" lon="10.0001"><time>2026-01-01T00:01:00Z
    XML
    f.close
    f.path
  end

  let(:gpx_file) { Rack::Test::UploadedFile.new(malformed_gpx_path, 'application/xml') }
  let(:import) { create(:import, user:, name: 'malformed.gpx', source: 'gpx') }

  before { import.file.attach(gpx_file) }
  after  { FileUtils.rm_f(malformed_gpx_path) }

  it 'raises Nokogiri::XML::SyntaxError instead of silently accepting truncated input' do
    expect { Gpx::TrackImporter.new(import, user.id).call }
      .to raise_error(Nokogiri::XML::SyntaxError, /GPX parse error/)
  end
end
