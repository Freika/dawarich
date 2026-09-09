# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationTraceGenerator do
  it 'generates a deterministic mixed trip with contiguous labels' do
    trip = described_class.trip(
      legs: [{ mode: :walking, duration_s: 300, dt_s: 5 }, { mode: :driving, duration_s: 600, dt_s: 5 }],
      start_time: Time.zone.parse('2026-01-05 09:00:00 UTC'), seed: 42
    )
    expect(trip[:points].size).to be_within(5).of(180)
    expect(trip[:points].map { |p| p[:timestamp] }).to eq(trip[:points].map { |p| p[:timestamp] }.sort)
    expect(trip[:labels].map { |l| l[:mode] }).to eq(%i[walking driving])
    expect(trip[:labels].first[:end_ts]).to eq(trip[:labels].last[:start_ts])
    again = described_class.trip(legs: [{ mode: :walking, duration_s: 300, dt_s: 5 },
                                        { mode: :driving, duration_s: 600, dt_s: 5 }],
                                 start_time: Time.zone.parse('2026-01-05 09:00:00 UTC'), seed: 42)
    expect(again[:points]).to eq(trip[:points])
  end

  it 'produces mode-plausible speeds' do
    trip = described_class.trip(legs: [{ mode: :train, duration_s: 900, dt_s: 10 }],
                                start_time: Time.zone.parse('2026-01-05 09:00:00 UTC'), seed: 1)
    speeds_kmh = trip[:points].map { |p| p[:velocity] * 3.6 }
    expect(speeds_kmh.sum / speeds_kmh.size).to be_between(60, 160)
  end
end
