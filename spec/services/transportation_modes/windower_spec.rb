# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::Windower do
  def rows_for(speeds_mps, dt_s: 5, start_ts: 0, bearing_wobble: 5.0)
    ts = start_ts
    speeds_mps.each_with_index.map do |speed, i|
      dt = dt_s
      row = { point_id: i + 1, ts: ts, accuracy: 5.0, velocity: nil, motion_data: {},
              lon: 12.37 + (i * 0.0001), lat: 51.34, dt: i.zero? ? nil : dt,
              dist_m: i.zero? ? nil : speed * dt, bearing_deg: 90.0,
              speed_mps: speed, speed_valid: true,
              bearing_delta_deg: i.zero? ? nil : bearing_wobble }
      ts += dt
      row
    end
  end

  it 'produces overlapping windows with percentile speed features' do
    rows = rows_for([1.3] * 60) # 5 minutes of walking at 5s dt
    windows = described_class.call(rows)

    expect(windows.size).to be_between(8, 10)
    expect(windows.first[:start_ts]).to eq(0)
    expect(windows[1][:start_ts] - windows.first[:start_ts]).to eq(30)
    expect(windows.first[:speed_p50]).to be_within(0.2).of(1.3 * 3.6)
    expect(windows.first[:sparse]).to be false
    expect(windows.first[:gap_before]).to be false
  end

  it 'marks a chain break after a long gap' do
    before_gap = rows_for([1.3] * 24)
    after_gap = rows_for([12.0] * 24, start_ts: before_gap.last[:ts] + 900)
    after_gap.first[:dt] = 900
    windows = described_class.call(before_gap + after_gap)

    break_window = windows.find { |w| w[:gap_before] }
    expect(break_window).not_to be_nil
    expect(break_window[:start_ts]).to eq(after_gap.first[:ts])
  end

  it 'flags sparse windows by mean dt' do
    rows = rows_for([12.0] * 10, dt_s: 60)
    windows = described_class.call(rows)
    expect(windows).to all(include(sparse: true))
  end

  it 'skips windows with fewer than two valid speed samples' do
    rows = rows_for([1.3] * 60)
    rows.each { |r| r[:speed_valid] = false }
    rows[10][:speed_valid] = true
    expect(described_class.call(rows)).to be_empty
  end

  it 'aggregates per-mode hint means over window points' do
    rows = rows_for([12.0] * 12)
    rows.each { |r| r[:motion_data] = { 'motion' => ['driving'] } }
    windows = described_class.call(rows)
    expect(windows.first[:hints][:driving])
      .to be_within(0.01).of(TransportationModes::HintScorer::OVERLAND_BOOST)
  end
end
