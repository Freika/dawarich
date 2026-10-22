# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::SegmentAssembler do
  # 900s trip at 5s dt: walking (1.3 m/s) for 300s, then driving (12 m/s).
  def build_rows
    (0...180).map do |i|
      ts = i * 5
      speed = ts <= 300 ? 1.3 : 12.0
      { point_id: i + 1, ts: ts, accuracy: 5.0, velocity: nil, motion_data: {},
        lon: 12.3712 + (i * 0.0002), lat: 51.3402,
        dt: i.zero? ? nil : 5, dist_m: i.zero? ? nil : speed * 5,
        bearing_deg: 90.0, speed_mps: speed, speed_valid: true,
        bearing_delta_deg: i.zero? ? nil : 3.0 }
    end
  end

  def build_windows_and_decoded(rows, boundary_ts: 300)
    windows = (0..(rows.last[:ts] - 60)).step(30).map do |start_ts|
      { start_ts: start_ts, end_ts: start_ts + 60, mean_dt: 5.0, hints: {},
        sparse: false, gap_before: false, point_ids: [] }
    end
    decoded = windows.map do |w|
      mid = w[:start_ts] + 30
      { mode: mid <= boundary_ts ? :walking : :driving, posterior: 0.9 }
    end
    [windows, decoded]
  end

  it 'assembles contiguous same-mode runs into time-anchored segments with stats' do
    rows = build_rows
    windows, decoded = build_windows_and_decoded(rows)
    segments = described_class.call(rows: rows, windows: windows, decoded: decoded)

    expect(segments.size).to eq(2)
    walking, driving = segments
    expect(walking[:mode]).to eq(:walking)
    expect(driving[:mode]).to eq(:driving)
    expect(walking[:start_at].to_i).to eq(0)
    expect(walking[:end_at].to_i).to be_within(35).of(300)
    expect(driving[:end_at].to_i).to eq(rows.last[:ts])
    expect(walking[:distance]).to be_within(50).of(1.3 * 300)
    expect(driving[:avg_speed]).to be_within(5.0).of(12.0 * 3.6)
    expect(walking[:path_wkt]).to start_with('LINESTRING')
    expect(walking[:confidence]).to eq(:high)
    expect(walking[:confidence_score]).to be_within(0.01).of(0.9)
    expect(walking[:source]).to eq('inferred')
  end

  it 'segments never overlap and are sorted' do
    rows = build_rows
    windows, decoded = build_windows_and_decoded(rows)
    segments = described_class.call(rows: rows, windows: windows, decoded: decoded)
    segments.each_cons(2) do |a, b|
      expect(a[:end_at]).to be <= b[:start_at]
    end
  end

  it 'clips auto segments around preserved corrected segments' do
    rows = build_rows
    windows, decoded = build_windows_and_decoded(rows)
    preserved = TrackSegment.new(start_at: Time.zone.at(400), end_at: Time.zone.at(600),
                                 transportation_mode: :bus, corrected_at: Time.current)
    segments = described_class.call(rows: rows, windows: windows, decoded: decoded,
                                    preserved: [preserved])

    segments.each do |seg|
      overlap = [seg[:start_at].to_i, 400].max < [seg[:end_at].to_i, 600].min
      expect(overlap).to be(false), "segment #{seg[:mode]} overlaps preserved range"
    end
    driving_parts = segments.select { |s| s[:mode] == :driving }
    expect(driving_parts.size).to eq(2)
  end

  it 'drops auto slivers shorter than the minimum' do
    rows = build_rows
    windows, decoded = build_windows_and_decoded(rows)
    preserved = TrackSegment.new(start_at: Time.zone.at(310), end_at: Time.zone.at(880),
                                 transportation_mode: :bus, corrected_at: Time.current)
    segments = described_class.call(rows: rows, windows: windows, decoded: decoded,
                                    preserved: [preserved])
    driving_parts = segments.select { |s| s[:mode] == :driving }
    expect(driving_parts.map { |s| s[:end_at].to_i - s[:start_at].to_i }).to all(be >= 30)
  end

  it 'marks runs containing hinted windows as hints+inferred' do
    rows = build_rows
    windows, decoded = build_windows_and_decoded(rows)
    windows[1][:hints] = { driving: 1.0 }
    segments = described_class.call(rows: rows, windows: windows, decoded: decoded)
    expect(segments.first[:source]).to eq('hints+inferred')
  end
end
