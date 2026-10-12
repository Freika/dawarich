# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'GPX orphan <trkpt> before any <trk> gets a distinct tracker_id' do
  let(:user) { create(:user) }
  let(:import) { create(:import, user: user, name: 'orphan.gpx', source: 'gpx') }

  let(:gpx_path) do
    file = Tempfile.new(['orphan', '.gpx'])
    file.write(gpx_content)
    file.close
    file.path
  end

  let(:base_time) { 1.hour.ago }

  let(:gpx_content) do
    orphan = %(<trkpt lat="52.0" lon="13.0"><time>#{base_time.utc.iso8601}</time></trkpt>)

    seg = (0..3).map do |i|
      t = (base_time + 600 + (i * 60)).utc.iso8601
      %(<trkpt lat="#{52.52 + (i * 0.0001)}" lon="#{13.405 + (i * 0.0001)}"><time>#{t}</time></trkpt>)
    end.join("\n")

    <<~GPX
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
        #{orphan}
        <trk>
          <trkseg>#{seg}</trkseg>
        </trk>
      </gpx>
    GPX
  end

  it 'orphan trkpt does not share tracker_id with the first real segment' do
    Gpx::TrackImporter.new(import, user.id, gpx_path).call

    tracker_ids = Point.where(import_id: import.id).pluck(:tracker_id).uniq
    expect(tracker_ids.size).to eq(2)
    expect(tracker_ids).to include("import-#{import.id}-orphan")
  end
end
