# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe 'GPX multi-segment import does not merge segments into one track' do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end

  let(:gpx_path) do
    file = Tempfile.new(['multi_segment', '.gpx'])
    file.write(gpx_content)
    file.close
    file.path
  end

  let(:base_time) { 1.hour.ago }

  let(:gpx_content) do
    seg_a = (0..3).map do |i|
      t = (base_time + (i * 60)).utc.iso8601
      %(<trkpt lat="#{52.52 + (i * 0.0001)}" lon="#{13.405 + (i * 0.0001)}"><time>#{t}</time></trkpt>)
    end.join("\n")

    seg_b = (0..3).map do |i|
      t = (base_time + 600 + (i * 60)).utc.iso8601
      %(<trkpt lat="#{48.8566 + (i * 0.0001)}" lon="#{2.3522 + (i * 0.0001)}"><time>#{t}</time></trkpt>)
    end.join("\n")

    <<~GPX
      <?xml version="1.0" encoding="UTF-8"?>
      <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
        <trk>
          <name>Two-segment trip</name>
          <trkseg>#{seg_a}</trkseg>
          <trkseg>#{seg_b}</trkseg>
        </trk>
      </gpx>
    GPX
  end

  let(:import) { create(:import, user: user, name: 'multi_segment.gpx', source: 'gpx') }

  before do
    import.file.attach(
      io: File.open(gpx_path),
      filename: 'multi_segment.gpx',
      content_type: 'application/gpx+xml'
    )
    Gpx::TrackImporter.new(import, user.id, gpx_path).call
  end

  it 'tags each segment with a distinct synthetic tracker_id' do
    tracker_ids = Point.where(import_id: import.id).pluck(:tracker_id).uniq
    expect(tracker_ids.size).to eq(2)
    expect(tracker_ids).to all(start_with('gpx-'))
    expect(tracker_ids).to all(match(/-trk-0-seg-[01]\z/))
  end

  it 'generates one track per segment, with no phantom Berlin-Paris leg' do
    Tracks::IncrementalGenerator.new(user).call

    expect(user.tracks.count).to eq(2)
    expect(user.tracks.maximum(:distance) || 0).to be < 5_000
  end

  it 'each track is scoped to a single segment' do
    Tracks::IncrementalGenerator.new(user).call

    user.tracks.each do |track|
      tracker_ids_in_track = track.points.pluck(:tracker_id).uniq
      expect(tracker_ids_in_track.size).to eq(1)
      expect(tracker_ids_in_track.first).to eq(track.tracker_id)
    end
  end
end
