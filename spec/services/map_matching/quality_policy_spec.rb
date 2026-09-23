# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MapMatching::QualityPolicy do
  let(:geometry) do
    { 'type' => 'LineString', 'coordinates' => [[13.4, 52.5], [13.41, 52.51]] }
  end

  it 'accepts valid geometry with matched coverage without assuming a confidence range' do
    decision = described_class.call(
      geometry:, stats: { 'matched' => 2, 'confidence_score' => 42.0 }, input_point_count: 2
    )

    expect(decision).to be_accepted
    expect(described_class::VERSION).to eq(1)
  end

  it 'rejects empty coverage' do
    decision = described_class.call(
      geometry:, stats: { 'matched' => 0, 'interpolated' => 0 }, input_point_count: 2
    )

    expect(decision).not_to be_accepted
    expect(decision.reasons).to include('no_matched_points')
  end

  it 'rejects malformed geometry' do
    decision = described_class.call(
      geometry: { 'type' => 'LineString', 'coordinates' => [[13.4, 52.5]] },
      stats: { 'matched' => 2 }, input_point_count: 2
    )

    expect(decision.reasons).to include('invalid_geometry')
  end
end
