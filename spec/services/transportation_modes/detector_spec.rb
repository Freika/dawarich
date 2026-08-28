# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::Detector do
  let(:user) { create(:user) }

  def create_track_with_trip(legs, seed: 42)
    trip = TransportationTraceGenerator.trip(
      legs: legs, start_time: Time.zone.parse('2026-01-05 09:00 UTC'), seed: seed
    )
    track = create(:track, user: user,
                           start_at: Time.zone.at(trip[:points].first[:timestamp]),
                           end_at: Time.zone.at(trip[:points].last[:timestamp]))
    now = Time.current
    Point.insert_all(trip[:points].map do |p|
      { user_id: user.id, track_id: track.id, timestamp: p[:timestamp],
        lonlat: "SRID=4326;POINT(#{p[:lon]} #{p[:lat]})",
        accuracy: p[:accuracy], velocity: p[:velocity].to_s,
        created_at: now, updated_at: now }
    end)
    [track, trip]
  end

  it 'detects a mixed walk-drive trip as time-anchored segments' do
    track, trip = create_track_with_trip(
      [{ mode: :walking, duration_s: 300, dt_s: 5 }, { mode: :driving, duration_s: 600, dt_s: 5 }]
    )
    segments = described_class.new(track).call

    expect(segments.map { |s| s[:mode] }).to eq(%i[walking driving])
    expect(segments.first[:start_at].to_i).to eq(trip[:points].first[:timestamp])
    expect(segments.last[:end_at].to_i).to eq(trip[:points].last[:timestamp])
    expect(segments.first[:path_wkt]).to start_with('LINESTRING')
    boundary = trip[:labels].first[:end_ts]
    expect(segments.first[:end_at].to_i).to be_within(60).of(boundary)
  end

  it 'respects enabled_modes' do
    track, = create_track_with_trip([{ mode: :running, duration_s: 600, dt_s: 5 }])
    segments = described_class.new(track, enabled_modes: %i[walking cycling driving]).call
    expect(segments.map { |s| s[:mode] }.uniq - %i[walking cycling driving]).to be_empty
  end

  it 'leaves preserved corrected ranges un-overlapped' do
    track, trip = create_track_with_trip(
      [{ mode: :walking, duration_s: 300, dt_s: 5 }, { mode: :driving, duration_s: 600, dt_s: 5 }]
    )
    mid = trip[:points][60][:timestamp]
    preserved = create(:track_segment, track: track, transportation_mode: :bus,
                                       start_index: nil, end_index: nil,
                                       start_at: Time.zone.at(mid), end_at: Time.zone.at(mid + 120),
                                       corrected_at: Time.current)

    segments = described_class.new(track, preserved: [preserved]).call
    segments.each do |seg|
      overlap = [seg[:start_at].to_i, mid].max < [seg[:end_at].to_i, mid + 120].min
      expect(overlap).to be(false)
    end
  end

  it 'returns a single unknown segment for degenerate tracks' do
    track = create(:track, user: user)
    segments = described_class.new(track).call
    expect(segments.size).to eq(1)
    expect(segments.first[:mode]).to eq(:unknown)
    expect(segments.first[:source]).to eq('default')
  end

  it 'falls back to unknown when a pipeline stage raises' do
    track, = create_track_with_trip([{ mode: :walking, duration_s: 300, dt_s: 5 }])
    allow(TransportationModes::FeatureExtractor).to receive(:call).and_raise(StandardError, 'boom')

    segments = described_class.new(track).call
    expect(segments.size).to eq(1)
    expect(segments.first[:mode]).to eq(:unknown)
  end
end
