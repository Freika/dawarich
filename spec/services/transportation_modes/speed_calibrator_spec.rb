# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::SpeedCalibrator do
  def rows_with_ratio(ratio, count: 30, derived_mps: 15.0)
    Array.new(count) do |i|
      { ts: i * 10, velocity: (derived_mps * ratio).round(3), dist_m: derived_mps * 10, dt: 10 }
    end
  end

  it 'leaves velocities untouched when stored matches derived (m/s)' do
    rows = rows_with_ratio(1.0)
    described_class.call(rows)
    expect(rows.first[:velocity]).to be_within(0.01).of(15.0)
  end

  it 'rescales km/h velocities to m/s' do
    rows = rows_with_ratio(3.6)
    described_class.call(rows)
    expect(rows.first[:velocity]).to be_within(0.1).of(15.0)
  end

  it 'rescales knots to m/s' do
    rows = rows_with_ratio(1.944)
    described_class.call(rows)
    expect(rows.first[:velocity]).to be_within(0.1).of(15.0)
  end

  it 'rescales mph to m/s' do
    rows = rows_with_ratio(2.237)
    described_class.call(rows)
    expect(rows.first[:velocity]).to be_within(0.1).of(15.0)
  end

  it 'drops stored velocities entirely when the ratio matches no known unit' do
    rows = rows_with_ratio(8.0)
    described_class.call(rows)
    expect(rows.map { |r| r[:velocity] }).to all(be_nil)
  end

  it 'does nothing below the sample floor' do
    rows = rows_with_ratio(3.6, count: 5)
    described_class.call(rows)
    expect(rows.first[:velocity]).to be_within(0.1).of(54.0)
  end

  it 'never uses negative or zero velocities as calibration samples and leaves negatives as-is' do
    rows = rows_with_ratio(3.6) +
           [{ ts: 999, velocity: -1.0, dist_m: 150.0, dt: 10 },
            { ts: 1009, velocity: 0.0, dist_m: nil, dt: 10 }]
    described_class.call(rows)

    expect(rows[0][:velocity]).to be_within(0.1).of(15.0)
    expect(rows[-2][:velocity]).to eq(-1.0)
    expect(rows[-1][:velocity]).to eq(0.0)
  end
end
