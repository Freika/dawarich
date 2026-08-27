# frozen_string_literal: true

require 'rails_helper'

VEHICLE_HINTS = {
  driving: TransportationModes::HintScorer::OVERLAND_BOOST,
  train: TransportationModes::HintScorer::OVERLAND_BOOST *
         TransportationModes::HintScorer::TRAIN_SHARE_OF_VEHICLE_HINT
}.freeze

RSpec.describe TransportationModes::Emissions do
  def window(overrides = {})
    { start_ts: 0, end_ts: 60, mean_dt: 5.0, speed_p50: 5.0, speed_p85: 6.0, speed_p95: 7.0,
      heading_change_rate: 10.0, motion_variance: 1.0, stop_fraction: 0.1,
      hints: {}, sparse: false }.merge(overrides)
  end

  it 'prefers walking for a walking-shaped window' do
    w = window(speed_p50: 4.5, speed_p95: 6.0, heading_change_rate: 12.0,
               motion_variance: 1.5, stop_fraction: 0.1)
    ll = described_class.log_likelihoods(w, enabled: described_class::INFERRED_MODES)
    expect(ll.max_by { |_, v| v }.first).to eq(:walking)
  end

  it 'separates train from driving via smoothness at overlapping speed' do
    smooth = window(speed_p50: 95.0, speed_p95: 120.0, heading_change_rate: 0.2,
                    motion_variance: 4.0, stop_fraction: 0.02)
    jerky = window(speed_p50: 95.0, speed_p95: 130.0, heading_change_rate: 1.5,
                   motion_variance: 20.0, stop_fraction: 0.1)
    expect(described_class.log_likelihoods(smooth, enabled: described_class::INFERRED_MODES)
      .max_by { |_, v| v }.first).to eq(:train)
    expect(described_class.log_likelihoods(jerky, enabled: described_class::INFERRED_MODES)
      .max_by { |_, v| v }.first).to eq(:driving)
  end

  it 'classifies an autobahn cruise with a generic vehicle hint as driving' do
    # Regression: smoothed-velocity trackers make 100+ km/h highway cruising
    # look train-like (variance ~0, heading rate ~0.2); the vehicle hint plus
    # the train prior must keep it driving (real trip 1525736, 2026-05-28 data).
    w = window(speed_p50: 104.4, speed_p95: 107.0, heading_change_rate: 0.3,
               motion_variance: 1.0, stop_fraction: 0.0, hints: VEHICLE_HINTS)
    ll = described_class.log_likelihoods(w, enabled: described_class::INFERRED_MODES)
    expect(ll.max_by { |_, v| v }.first).to eq(:driving)
  end

  it 'still reaches train for a clear rail signature despite a generic vehicle hint' do
    # ICE-like: sustained 180 km/h, near-zero heading change — no car does this.
    w = window(speed_p50: 180.0, speed_p95: 210.0, heading_change_rate: 0.15,
               motion_variance: 6.0, stop_fraction: 0.02, hints: VEHICLE_HINTS)
    ll = described_class.log_likelihoods(w, enabled: described_class::INFERRED_MODES)
    expect(ll.max_by { |_, v| v }.first).to eq(:train)
  end

  it 'still prefers train for an unhinted smooth high-speed cruise' do
    w = window(speed_p50: 104.4, speed_p95: 130.0, heading_change_rate: 0.2,
               motion_variance: 4.0, stop_fraction: 0.02)
    ll = described_class.log_likelihoods(w, enabled: described_class::INFERRED_MODES)
    expect(ll.max_by { |_, v| v }.first).to eq(:train)
  end

  it 'classifies slow smooth city driving with a driving hint as driving, not cycling' do
    w = window(speed_p50: 28.8, speed_p95: 32.0, heading_change_rate: 1.3,
               motion_variance: 4.0, stop_fraction: 0.0,
               hints: { driving: TransportationModes::HintScorer::OVERLAND_BOOST })
    ll = described_class.log_likelihoods(w, enabled: described_class::INFERRED_MODES)
    expect(ll.max_by { |_, v| v }.first).to eq(:driving)
  end

  it 'lets a strong bus hint beat kinematics' do
    w = window(speed_p50: 30.0, speed_p95: 50.0, heading_change_rate: 1.0,
               motion_variance: 12.0, stop_fraction: 0.2, hints: { bus: Math.log(4.6) })
    ll = described_class.log_likelihoods(w, enabled: described_class::INFERRED_MODES + [:bus])
    expect(ll.max_by { |_, v| v }.first).to eq(:bus)
  end

  it 'never emits hint-only modes without a hint' do
    w = window(speed_p50: 30.0)
    ll = described_class.log_likelihoods(w, enabled: described_class::INFERRED_MODES + %i[bus boat motorcycle])
    expect(ll.keys & %i[bus boat motorcycle]).to be_empty
  end

  it 'omits disabled modes' do
    w = window(speed_p50: 95.0, speed_p95: 120.0, heading_change_rate: 0.2,
               motion_variance: 4.0, stop_fraction: 0.02)
    ll = described_class.log_likelihoods(w, enabled: %i[walking driving])
    expect(ll.keys).to match_array(%i[walking driving])
  end

  it 'still classifies plausibly on sparse windows via speed alone' do
    w = window(speed_p50: 50.0, speed_p95: 70.0, heading_change_rate: nil,
               motion_variance: nil, stop_fraction: nil, sparse: true, mean_dt: 60.0)
    ll = described_class.log_likelihoods(w, enabled: described_class::INFERRED_MODES)
    expect(ll.max_by { |_, v| v }.first).to eq(:driving)
  end
end
