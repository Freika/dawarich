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

  it 'deletes rows whose index range matches no points' do
    track = create(:track, user: user)
    seg = create(:track_segment, track: track, start_index: 50, end_index: 60,
                                 start_at: nil, end_at: nil)

    described_class.perform_now

    expect(TrackSegment.exists?(seg.id)).to be false
  end

  it 'deletes a segment whose point slice is incomplete (points deleted since) instead of anchoring it wrongly' do
    track = build_track_with_points(legs: [{ mode: :walking, duration_s: 120, dt_s: 10 }])
    # Index range reaches past the surviving points — a truncated slice would
    # otherwise anchor to the wrong end timestamp.
    seg = create(:track_segment, track: track, transportation_mode: :walking,
                                 start_index: 8, end_index: 30, start_at: nil, end_at: nil)

    described_class.perform_now

    expect(TrackSegment.exists?(seg.id)).to be false
  end

  it 'skips a segment colliding with an already-anchored twin instead of halting the backfill' do
    track = build_track_with_points(legs: [{ mode: :walking, duration_s: 120, dt_s: 10 }])
    t0 = track.points.order(:timestamp, :id).limit(3).pick(:timestamp)
    create(:track_segment, track: track, transportation_mode: :walking,
                           start_index: nil, end_index: nil,
                           start_at: Time.zone.at(t0), end_at: Time.zone.at(t0 + 60))
    colliding = create(:track_segment, track: track, transportation_mode: :walking,
                       start_index: 0, end_index: 5, start_at: nil, end_at: nil)
    survivor = create(:track_segment, track: track, transportation_mode: :walking,
                      start_index: 6, end_index: 9, start_at: nil, end_at: nil)

    expect { described_class.perform_now }.not_to raise_error

    expect(TrackSegment.exists?(colliding.id)).to be false
    expect(survivor.reload.start_at).to be_present
  end

  it 'preserves manually-corrected segments even when their slice cannot be anchored' do
    track = build_track_with_points(legs: [{ mode: :walking, duration_s: 120, dt_s: 10 }])
    seg = create(:track_segment, track: track, transportation_mode: :cycling,
                                 corrected_at: 1.week.ago,
                                 start_index: 8, end_index: 30, start_at: nil, end_at: nil)

    described_class.perform_now

    seg.reload
    expect(seg.start_at).to be_nil
    expect(seg.start_index).to eq(8)
    expect(seg.transportation_mode).to eq('cycling')
  end
end
