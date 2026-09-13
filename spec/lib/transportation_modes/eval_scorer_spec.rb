# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TransportationModes::EvalScorer do
  let(:labels) { [{ mode: :walking, start_ts: 0, end_ts: 300 }, { mode: :driving, start_ts: 300, end_ts: 900 }] }
  let(:points) { (0...900).step(10).map { |t| { timestamp: t } } }

  it 'scores perfect prediction as 1.0/1.0' do
    result = described_class.score(predicted: labels, labels: labels, points: points)
    expect(result[:point_accuracy]).to eq(1.0)
    expect(result[:boundary_f1]).to eq(1.0)
  end

  it 'penalizes a missed boundary' do
    predicted = [{ mode: :driving, start_ts: 0, end_ts: 900 }]
    result = described_class.score(predicted: predicted, labels: labels, points: points)
    expect(result[:point_accuracy]).to be_within(0.02).of(600.0 / 900)
    expect(result[:boundary_f1]).to be < 1.0
  end

  it 'reports per-mode precision and recall' do
    predicted = [{ mode: :driving, start_ts: 0, end_ts: 900 }]
    result = described_class.score(predicted: predicted, labels: labels, points: points)
    expect(result[:per_mode][:driving][:recall]).to eq(1.0)
    expect(result[:per_mode][:driving][:precision]).to be_within(0.02).of(600.0 / 900)
    expect(result[:per_mode][:walking][:recall]).to eq(0.0)
  end
end
