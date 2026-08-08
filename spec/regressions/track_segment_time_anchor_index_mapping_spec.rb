# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Time-anchor backfill index mapping' do
  let(:user) { create(:user) }

  def track_with_points(count)
    base = Time.zone.parse('2026-01-05 09:00 UTC')
    track = create(:track, user: user, start_at: base, end_at: base + (count * 10).seconds)
    count.times do |i|
      create(:point, user: user, track: track, timestamp: (base + (i * 10).seconds).to_i,
                     lonlat: "SRID=4326;POINT(#{12.37 + (i * 0.001)} #{51.34 + (i * 0.001)})")
    end
    track
  end

  it 'anchors every segment of a track to its own slice, not a neighbour’s' do
    track = track_with_points(30)
    first = create(:track_segment, track: track, transportation_mode: :walking,
                                   start_index: 0, end_index: 9, start_at: nil, end_at: nil)
    middle = create(:track_segment, track: track, transportation_mode: :driving,
                                    start_index: 10, end_index: 19, start_at: nil, end_at: nil)
    last = create(:track_segment, track: track, transportation_mode: :walking,
                                  start_index: 20, end_index: 29, start_at: nil, end_at: nil)

    TrackSegments::TimeAnchorBackfillJob.perform_now

    stamps = track.points.order(:timestamp, :id).pluck(:timestamp)
    expect([first, middle, last].map { |s| s.reload.start_at.to_i })
      .to eq([stamps[0], stamps[10], stamps[20]])
    expect([first, middle, last].map { |s| s.reload.end_at.to_i })
      .to eq([stamps[9], stamps[19], stamps[29]])
  end

  it 'keeps slices contiguous and non-overlapping across many segments' do
    track = track_with_points(30)
    6.times do |i|
      create(:track_segment, track: track, transportation_mode: :walking,
                             start_index: i * 5, end_index: (i * 5) + 4, start_at: nil, end_at: nil)
    end

    TrackSegments::TimeAnchorBackfillJob.perform_now

    anchored = track.track_segments.order(:start_at).pluck(:start_at, :end_at)
    expect(anchored.size).to eq(6)
    anchored.each_cons(2) { |(_, prev_end), (next_start, _)| expect(prev_end).to be < next_start }
  end

  it 'leaves a segment whose index range exceeds the track unanchored' do
    track = track_with_points(5)
    seg = create(:track_segment, track: track, transportation_mode: :walking,
                                 start_index: 0, end_index: 40, start_at: nil, end_at: nil,
                                 corrected_at: Time.current)

    TrackSegments::TimeAnchorBackfillJob.perform_now

    expect(seg.reload.start_at).to be_nil
  end
end
