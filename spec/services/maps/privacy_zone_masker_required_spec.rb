# frozen_string_literal: true

require 'rails_helper'

# A map read that forgets its masker must fail loudly, not read unmasked.
# Callers that read unmasked on purpose pass Maps::PrivacyZoneMasker.none.
RSpec.describe 'Map reads require an explicit privacy zone masker' do
  let(:user) { create(:user) }
  let(:stat) { create(:stat, user: user) }
  let(:dates) { { start_date: '2024-01-01', end_date: '2024-01-31' } }

  {
    'Timeline::DayAssembler' => -> { Timeline::DayAssembler.new(user, start_at: '', end_at: '') },
    'Visits::PointCenters' => -> { Visits::PointCenters.new(user, visit_ids: []) },
    'Visits::Finder' => -> { Visits::Finder.new(user, {}) },
    'Visits::FindWithinBoundingBox' => -> { Visits::FindWithinBoundingBox.new(user, {}) },
    'LocationSearch::PointFinder' => -> { LocationSearch::PointFinder.new(user, {}) },
    'Maps::HexagonRequestHandler' => -> { Maps::HexagonRequestHandler.new(params: {}, user: user) },
    'Maps::HexagonCenterManager' => -> { Maps::HexagonCenterManager.new(stat: stat, user: user) },
    'Maps::FogHexagons' => -> { Maps::FogHexagons.new(user: user, **dates) },
    'Maps::BoundsCalculator' => -> { Maps::BoundsCalculator.new(user: user, **dates) },
    'Achievements::CityRule' => -> { Achievements::CityRule.call(user, nil, nil) },
    'Achievements::ObservedTime' => -> { Achievements::ObservedTime.new(user) },
    'Tracks::VectorTileQuery' => -> { Tracks::VectorTileQuery.new(scope: user.tracks, z: 0, x: 0, y: 0) },
    'Stat#calculate_data_bounds' => -> { stat.calculate_data_bounds }
  }.each do |name, build|
    it "#{name} raises without a masker" do
      expect { instance_exec(&build) }.to raise_error(ArgumentError, /privacy_zone_masker/)
    end
  end

  it 'rejects an explicit nil instead of reading unmasked' do
    expect { stat.calculate_data_bounds(privacy_zone_masker: nil) }.to raise_error(NoMethodError)
  end
end
