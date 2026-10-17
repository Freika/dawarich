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

  describe 'Overland motion_confidence' do
    it 'keeps the fixed Overland boost when motion_confidence is absent' do
      expect(described_class.call({ 'motion' => %w[cycling] })[:cycling]).to eq(described_class::OVERLAND_BOOST)
    end

    it 'scales the hint through the probability curve below 1' do
      hints = described_class.call({ 'motion' => %w[cycling], 'motion_confidence' => 0.5 })
      expect(hints[:cycling]).to be_within(0.001).of(described_class.boost(0.5))
      expect(hints[:cycling]).to be < described_class::OVERLAND_BOOST
    end

    it 'gives the full Overland boost at 1.0' do
      hints = described_class.call({ 'motion' => %w[cycling], 'motion_confidence' => 1.0 })
      expect(hints[:cycling]).to be_within(0.001).of(described_class::OVERLAND_BOOST)
    end
  end

  describe '.certain_mode' do
    it 'returns the mode when the device is certain' do
      expect(described_class.certain_mode({ 'motion' => %w[driving], 'motion_confidence' => 1.0 })).to eq(:driving)
      expect(described_class.certain_mode({ 'motion' => %w[automotive], 'motion_confidence' => '1' })).to eq(:driving)
    end

    it 'is nil below full confidence or without confidence' do
      expect(described_class.certain_mode({ 'motion' => %w[driving], 'motion_confidence' => 0.99 })).to be_nil
      expect(described_class.certain_mode({ 'motion' => %w[driving] })).to be_nil
    end

    it 'is nil when motion names several or no known modes' do
      expect(described_class.certain_mode({ 'motion' => %w[driving walking], 'motion_confidence' => 1.0 })).to be_nil
      expect(described_class.certain_mode({ 'motion' => %w[unknown], 'motion_confidence' => 1.0 })).to be_nil
      expect(described_class.certain_mode({ 'motion_confidence' => 1.0 })).to be_nil
      expect(described_class.certain_mode(nil)).to be_nil
    end
  end
end
