# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TrackSegments::TimeAnchorBackfillJob do
  let(:user) { create(:user) }

  def build_track_with_points(legs:, seed: 7)
    trip = TransportationTraceGenerator.trip(
      legs: legs, start_time: Time.zone.parse('2026-01-05 09:00 UTC'), seed: seed
    )
    track = create(:track, user: user,
                           start_at: Time.zone.at(trip[:points].first[:timestamp]),
                           end_at: Time.zone.at(trip[:points].last[:timestamp]))
    trip[:points].each do |p|
      create(:point, user: user, track: track, timestamp: p[:timestamp],
                     lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})")
    end
    track
  end

  it 'anchors an index-based segment to point timestamps and geometry' do
    track = build_track_with_points(legs: [{ mode: :walking, duration_s: 120, dt_s: 10 }])
    seg = create(:track_segment, track: track, transportation_mode: :walking,
                                 start_index: 2, end_index: 5, start_at: nil, end_at: nil)

    described_class.perform_now

    seg.reload
    ordered = track.points.order(:timestamp, :id).pluck(:timestamp)
    expect(seg.start_at.to_i).to eq(ordered[2])
    expect(seg.end_at.to_i).to eq(ordered[5])
    expect(seg.path).to be_present
    expect(seg.path.points.size).to eq(4)
  end

  it 'is idempotent and skips already-anchored rows' do
    seg = create(:track_segment, :anchored)

    expect { described_class.perform_now }.not_to(change { seg.reload.start_at })
  end

  it 'clears indexes on rows whose index range matches no points' do
    track = create(:track, user: user)
    seg = create(:track_segment, track: track, start_index: 50, end_index: 60,
                                 start_at: nil, end_at: nil)

    described_class.perform_now

    seg.reload
    expect(seg.start_at).to be_nil
    expect(seg.start_index).to be_nil
    expect(seg.end_index).to be_nil
  end

  it 'refuses to anchor a segment whose point slice is incomplete (points deleted since)' do
    track = build_track_with_points(legs: [{ mode: :walking, duration_s: 120, dt_s: 10 }])
    # Index range reaches past the surviving points — a truncated slice would
    # otherwise anchor to the wrong end timestamp.
    seg = create(:track_segment, track: track, transportation_mode: :walking,
                                 start_index: 8, end_index: 30, start_at: nil, end_at: nil)

    described_class.perform_now

    seg.reload
    expect(seg.start_at).to be_nil
    expect(seg.start_index).to be_nil
  end
end
