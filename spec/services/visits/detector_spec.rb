# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Detector do
  let(:user) { create(:user) }

  # The issue is likely with how we're creating the test points
  # Let's make them more realistic with proper spacing in time and location
  let(:points) do
    [
      # First visit - 3 points close together
      build_stubbed(:point, lonlat: 'POINT(-74.0060 40.7128)', timestamp: 1.hour.ago.to_i),
      build_stubbed(:point, lonlat: 'POINT(-74.0061 40.7129)', timestamp: 50.minutes.ago.to_i),
      build_stubbed(:point, lonlat: 'POINT(-74.0062 40.7130)', timestamp: 40.minutes.ago.to_i),

      # Gap in time (> MAXIMUM_VISIT_GAP)

      # Second visit - different location
      build_stubbed(:point, lonlat: 'POINT(-74.0500 40.7500)', timestamp: 10.minutes.ago.to_i),
      build_stubbed(:point, lonlat: 'POINT(-74.0501 40.7501)', timestamp: 5.minutes.ago.to_i)
    ]
  end

  subject { described_class.new(points) }

  describe '#detect_potential_visits' do
    before do
      allow(subject).to receive(:valid_visit?).and_return(true)
      allow(subject).to receive(:suggest_place_name).and_return('Test Place')
    end

    it 'identifies potential visits from points' do
      visits = subject.detect_potential_visits

      expect(visits.size).to eq(2)
      expect(visits.first[:points].size).to eq(3)
      expect(visits.last[:points].size).to eq(2)
    end

    it 'calculates visit properties correctly' do
      visits = subject.detect_potential_visits
      first_visit = visits.first

      # The center should be the average of the first 3 points
      expected_lat = (40.7128 + 40.7129 + 40.7130) / 3
      expected_lon = (-74.0060 + -74.0061 + -74.0062) / 3

      expect(first_visit[:duration]).to be_within(60).of(20.minutes.to_i)
      expect(first_visit[:center_lat]).to be_within(0.001).of(expected_lat)
      expect(first_visit[:center_lon]).to be_within(0.001).of(expected_lon)
      expect(first_visit[:radius]).to be > 0
      expect(first_visit[:suggested_name]).to eq('Test Place')
    end

    context 'with insufficient points for a visit' do
      let(:points) do
        [
          build_stubbed(:point, lonlat: 'POINT(-74.0060 40.7128)', timestamp: 1.hour.ago.to_i),
          # Large time gap
          build_stubbed(:point, lonlat: 'POINT(-74.0061 40.7129)', timestamp: 10.minutes.ago.to_i)
        ]
      end

      before do
        allow(subject).to receive(:valid_visit?).and_call_original
      end

      it 'does not create a visit' do
        visits = subject.detect_potential_visits
        expect(visits).to be_empty
      end
    end
  end
end
