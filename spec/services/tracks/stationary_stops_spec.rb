# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::StationaryStops do
  let(:latitude) { -40.0 }
  let(:meters_per_lon_degree) { 111_320 * Math.cos(latitude * Math::PI / 180) }

  def sample(minute, east_meters)
    [minute * 60, -140.0 + east_meters / meters_per_lon_degree, latitude]
  end

  describe '.radius_for' do
    it 'uses the visit radius when it is larger than the default' do
      user = create(:user, settings: { 'visit_radius_meters' => 300 })

      expect(described_class.radius_for(user)).to eq(300)
    end

    it 'never goes below the default radius' do
      user = create(:user, settings: { 'visit_radius_meters' => 30 })

      expect(described_class.radius_for(user)).to eq(100)
    end
  end

  describe '.break_indexes' do
    let(:threshold_seconds) { 10 * 60 }

    it 'keeps a short walk that leaves the radius between two stays out of the stop' do
      walk = [65, 130, 190, 130, 65]
      samples = (0..29).map { |minute| sample(minute, 0) } +
                walk.each_with_index.map { |meters, offset| sample(30 + offset, meters) } +
                (35..64).map { |minute| sample(minute, 0) }

      breaks = described_class.break_indexes(samples, threshold_seconds)

      expect(breaks).to include(29, 50)
      expect(breaks).not_to include(31, 32, 33)
    end

    it 'joins the parts of a stay whose readings scatter within the radius' do
      pattern = [0, 1, -1, 0.5, -0.5, 1, -1]
      samples = (0..40).map { |index| sample(index * 5, pattern[index % pattern.size] * 80) }

      breaks = described_class.break_indexes(samples, threshold_seconds).sort

      expect(breaks.first..breaks.last).to all(satisfy { |index| breaks.include?(index) })
    end
  end
end
