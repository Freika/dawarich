# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Multi-day GPX import stays partitioned in bulk segmentation' do
  let(:user) do
    create(:user, settings: {
             'minutes_between_routes' => 30,
             'meters_between_routes' => 500
           })
  end

  let(:day_one_ts) { Time.zone.parse('2025-06-01 10:00:00').to_i }
  let(:day_two_ts) { Time.zone.parse('2025-06-15 10:00:00').to_i }

  let(:nil_tracker_ts) { Time.zone.parse('2025-06-08 10:00:00').to_i }

  before do
    4.times do |i|
      create(
        :point,
        user: user,
        tracker_id: 'gpx-deviceA-trk-0',
        timestamp: day_one_ts + (i * 60),
        lonlat: "POINT(#{13.405 + (i * 0.0001)} #{52.52 + (i * 0.0001)})"
      )
      create(
        :point,
        user: user,
        tracker_id: 'gpx-deviceB-trk-0',
        timestamp: day_two_ts + (i * 60),
        lonlat: "POINT(#{2.3522 + (i * 0.0001)} #{48.8566 + (i * 0.0001)})"
      )
      create(
        :point,
        user: user,
        tracker_id: nil,
        timestamp: nil_tracker_ts + (i * 60),
        lonlat: "POINT(#{-0.1278 + (i * 0.0001)} #{51.5074 + (i * 0.0001)})"
      )
    end
  end

  it 'segmenting the full history returns one segment per tracker_id (including a separate NULL bucket)' do
    segments = Track.get_segments_with_points(
      user.id,
      day_one_ts - 3600,
      day_two_ts + 3600,
      30,
      500
    )

    tracker_ids = segments.map { |seg| seg[:tracker_id] }.sort_by(&:to_s)
    expect(tracker_ids).to eq([nil, 'gpx-deviceA-trk-0', 'gpx-deviceB-trk-0'])

    segments.each do |seg|
      timestamps = seg[:points].map(&:timestamp)
      span_seconds = timestamps.max - timestamps.min
      expect(span_seconds).to be < 3600
    end

    null_segment = segments.find { |seg| seg[:tracker_id].nil? }
    null_lonlats = null_segment[:points].map { |p| [p.lon.round(4), p.lat.round(4)] }.uniq.sort
    expect(null_lonlats).to all(satisfy { |lon, lat| lon < 0 && lat > 50 && lat < 52 })
  end
end
