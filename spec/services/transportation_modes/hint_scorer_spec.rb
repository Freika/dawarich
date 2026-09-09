# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::HintScorer do
  it 'boosts by Google probable activity probability' do
    motion_data = {
      'activityRecord' => {
        'probableActivities' => [
          { 'activityType' => 'IN_BUS', 'probability' => 0.9 },
          { 'activityType' => 'STILL', 'probability' => 0.1 }
        ]
      }
    }
    hints = described_class.call(motion_data)
    expect(hints[:bus]).to be_within(0.01).of(Math.log(1 + (described_class::PROBABILITY_SCALE * 0.9)))
    expect(hints).not_to have_key(:stationary)
  end

  it 'uses the default probability for bare activity strings' do
    hints = described_class.call({ 'activityType' => 'IN_RAIL_VEHICLE' })
    expected = Math.log(1 + (described_class::PROBABILITY_SCALE * described_class::DEFAULT_PROBABILITY))
    expect(hints[:train]).to be_within(0.01).of(expected)
  end

  it 'expands Overland vehicle motion to driving plus partial train support' do
    hints = described_class.call({ 'motion' => %w[driving stationary] })
    expect(hints[:driving]).to be_within(0.01).of(described_class::OVERLAND_BOOST)
    expect(hints[:train]).to be_within(0.01)
      .of(described_class::OVERLAND_BOOST * described_class::TRAIN_SHARE_OF_VEHICLE_HINT)
  end

  it 'does not expand explicit rail hints' do
    hints = described_class.call({ 'activityType' => 'IN_RAIL_VEHICLE' })
    expect(hints).not_to have_key(:driving)
  end

  it 'does not expand non-vehicle hints' do
    hints = described_class.call({ 'motion' => %w[walking] })
    expect(hints.keys).to eq([:walking])
  end

  it 'ignores OwnTracks monitoring-mode flags' do
    expect(described_class.call({ 'm' => 1, '_type' => 'location' })).to eq({})
  end

  it 'returns empty for nil or garbage input' do
    expect(described_class.call(nil)).to eq({})
    expect(described_class.call([])).to eq({})
    expect(described_class.call({ 'unrelated' => true })).to eq({})
  end
end
