# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::ConfidenceScorer do
  def score(**overrides)
    defaults = {
      duration_seconds: 1800,
      point_count: 9,
      accuracies: [10, 12, 8],
      radius_meters: 20,
      stay_radius_meters: 100,
      min_points: 3,
      place_match: nil
    }
    described_class.new(**defaults.merge(overrides)).call
  end

  it 'returns an integer score within 0..100 and a breakdown' do
    result = score

    expect(result[:score]).to be_between(0, 100)
    expect(result[:score]).to be_an(Integer)
    expect(result[:breakdown]).to be_a(Hash)
  end

  it 'scores a long, tight, accurate, area-matched stay in the high band' do
    result = score(duration_seconds: 3600, point_count: 30, accuracies: [5, 6, 7],
                   radius_meters: 10, place_match: :area)

    expect(result[:score]).to be >= 70
  end

  it 'scores a short, sparse, low-accuracy, place-less stay in the low band' do
    result = score(duration_seconds: 300, point_count: 3, accuracies: [120, 150, 100],
                   radius_meters: 95, place_match: nil)

    expect(result[:score]).to be < 40
  end

  it 'marks place_match unavailable and redistributes its weight when nil' do
    result = score(place_match: nil)

    expect(result[:breakdown][:place_match]).to eq('unavailable')
    expect(result[:score]).to be_between(0, 100)
  end

  it 'gives a higher score for an area match than for no place match, all else equal' do
    with_area = score(place_match: :area)
    without   = score(place_match: nil)

    expect(with_area[:score]).to be > without[:score]
  end

  it 'treats nil accuracies as the default 50 m without error' do
    expect { score(accuracies: [nil, nil]) }.not_to raise_error
  end
end
