# frozen_string_literal: true

require 'rails_helper'

# Feature values at each mode's profile centers — deterministic emissions.
DECODER_SPEC_CENTERS = {
  stationary: { speed_p50: 0.4, speed_p95: 1.5, heading_change_rate: 20.0,
                motion_variance: nil, stop_fraction: 0.9 },
    walking: { speed_p50: 4.5, speed_p95: 6.5, heading_change_rate: 12.0,
               motion_variance: 1.5, stop_fraction: 0.15 },
    running: { speed_p50: 10.0, speed_p95: 14.0, heading_change_rate: 6.0,
               motion_variance: 2.5, stop_fraction: 0.05 },
    cycling: { speed_p50: 17.0, speed_p95: 28.0, heading_change_rate: 3.0,
               motion_variance: 4.0, stop_fraction: 0.08 },
    driving: { speed_p50: 45.0, speed_p95: 95.0, heading_change_rate: 1.2,
               motion_variance: 18.0, stop_fraction: 0.15 },
    train: { speed_p50: 90.0, speed_p95: 140.0, heading_change_rate: 0.3,
             motion_variance: 8.0, stop_fraction: 0.05 },
    flying: { speed_p50: 500.0, speed_p95: 750.0, heading_change_rate: 0.1,
              motion_variance: 30.0, stop_fraction: 0.01 }
}.freeze

RSpec.describe TransportationModes::Decoder do
  def synthetic_windows(modes)
    modes.each_with_index.map do |mode, i|
      DECODER_SPEC_CENTERS.fetch(mode).merge(
        start_ts: i * 30, end_ts: (i * 30) + 60, mean_dt: 5.0,
        speed_p85: DECODER_SPEC_CENTERS.fetch(mode)[:speed_p95] * 0.9,
        hints: {}, sparse: false, gap_before: false, point_ids: []
      )
    end
  end

  let(:all_modes) { TransportationModes::Emissions::INFERRED_MODES }

  it 'decodes a clean walk-drive-walk sequence with boundaries at the transitions' do
    windows = synthetic_windows((%i[walking] * 6) + (%i[driving] * 12) + (%i[walking] * 6))
    out = described_class.call(windows, enabled: all_modes)
    expect(out.map { |d| d[:mode] }.chunk_while { |a, b| a == b }.map(&:first)).to eq(%i[walking driving walking])
  end

  it 'suppresses single-window flapping' do
    modes = %i[driving] * 10
    modes[5] = :cycling
    out = described_class.call(synthetic_windows(modes), enabled: all_modes)
    expect(out.map { |d| d[:mode] }.uniq).to eq([:driving])
  end

  it 'returns calibrated posteriors' do
    out = described_class.call(synthetic_windows(%i[walking] * 8), enabled: all_modes)
    expect(out).to all(satisfy { |d| d[:posterior] > 0.8 })
  end

  it 'decodes chains independently across gaps' do
    windows = synthetic_windows((%i[walking] * 4) + (%i[flying] * 4))
    windows[4][:gap_before] = true
    out = described_class.call(windows, enabled: all_modes)
    expect(out.map { |d| d[:mode] }.uniq).to eq(%i[walking flying])
  end

  it 'never emits disabled modes' do
    out = described_class.call(synthetic_windows(%i[running] * 6), enabled: %i[walking cycling])
    expect(out.map { |d| d[:mode] }.uniq - %i[walking cycling]).to be_empty
  end

  it 'returns empty for empty input' do
    expect(described_class.call([], enabled: all_modes)).to eq([])
  end
end
