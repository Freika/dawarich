# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::Preprocessor do
  def row(overrides = {})
    { point_id: 1, ts: 0, accuracy: 5.0, velocity: nil, motion_data: {},
      lon: 12.3712, lat: 51.3402, dt: nil, dist_m: nil, bearing_deg: nil }.merge(overrides)
  end

  it 'trusts stored zero velocity for parked points' do
    rows = [row(ts: 0, velocity: 0.0), row(ts: 10, velocity: 0.0, dt: 10, dist_m: 25.0)]
    out = described_class.call(rows)
    expect(out[1][:speed_mps]).to eq(0.0)
    expect(out[1][:speed_valid]).to be true
  end

  it 'derives speed from distance and time when velocity is absent' do
    rows = [row(ts: 0), row(ts: 10, dt: 10, dist_m: 40.0)]
    out = described_class.call(rows)
    expect(out[1][:speed_mps]).to eq(4.0)
    expect(out[1][:speed_valid]).to be true
  end

  it 'rescales stored velocities when the tracker reports km/h instead of m/s' do
    rows = Array.new(25) do |i|
      row(ts: i * 10, velocity: 54.0, dt: i.zero? ? nil : 10, dist_m: i.zero? ? nil : 150.0)
    end
    out = described_class.call(rows)

    expect(out[1][:speed_mps]).to be_within(0.1).of(15.0)
    expect(out[1][:speed_valid]).to be true
  end

  it 'masks negative stored velocity entirely — the point is an anomaly, not a data gap' do
    # Devices report speed = -1 when the fix is unreliable (iOS CLLocation /
    # Traccar Client JSON); deriving a speed from a suspect fix would launder
    # the anomaly, so the sample is invalidated outright.
    rows = [row(ts: 0), row(ts: 10, velocity: -1.0, dt: 10, dist_m: 40.0)]
    out = described_class.call(rows)
    expect(out[1][:speed_valid]).to be false
    expect(out[1][:speed_mps]).to be_nil
  end

  it 'invalidates speed on poor accuracy' do
    rows = [row(ts: 0), row(ts: 10, dt: 10, dist_m: 40.0, accuracy: 250.0)]
    expect(described_class.call(rows)[1][:speed_valid]).to be false
  end

  it 'masks physically implausible jumps' do
    rows = [row(ts: 0, velocity: 1.0), row(ts: 2, dt: 2, dist_m: 400.0)]
    expect(described_class.call(rows)[1][:speed_valid]).to be false
  end

  it 'keeps zero-dt rows in sequence without a speed sample' do
    rows = [row(ts: 0), row(ts: 0, dt: 0, dist_m: 3.0)]
    out = described_class.call(rows)
    expect(out.size).to eq(2)
    expect(out[1][:speed_valid]).to be false
  end

  it 'computes circular bearing deltas' do
    rows = [row(ts: 0), row(ts: 10, dt: 10, bearing_deg: 350.0), row(ts: 20, dt: 10, bearing_deg: 10.0)]
    expect(described_class.call(rows)[2][:bearing_delta_deg]).to be_within(0.1).of(20.0)
  end

  it 'does not derive a speed sample across a tracking gap' do
    gap = TransportationModes::Emissions::TUNING[:gap_reset_s] + 900
    rows = [row(ts: 0), row(ts: gap, dt: gap, dist_m: 15_000.0)]

    out = described_class.call(rows)

    expect(out[1][:speed_valid]).to be false
  end
end
