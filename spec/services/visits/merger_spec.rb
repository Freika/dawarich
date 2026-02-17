# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Merger do
  let(:user) { create(:user) }
  let(:points) { user.points }

  subject { described_class.new(points, user: user) }

  describe 'constants' do
    it 'has expected default values' do
      expect(described_class::MAXIMUM_VISIT_GAP).to eq(30.minutes)
      expect(described_class::DEFAULT_EXTENDED_MERGE_HOURS).to eq(2)
      expect(described_class::DEFAULT_TRAVEL_THRESHOLD_METERS).to eq(200)
      expect(described_class::SIGNIFICANT_MOVEMENT_THRESHOLD).to eq(50)
    end
  end

  describe '#merge_visits' do
    context 'when visits can be merged' do
      # visit1 and visit2 have centers ~15m apart (well within 50m threshold)
      # and a small time gap (10 minutes, well within 30 minute threshold)
      let(:points) { user.points.order(timestamp: :asc) }
      let!(:point1) { create(:point, user: user, timestamp: 2.hours.ago.to_i) }
      let!(:point2) { create(:point, user: user, timestamp: 50.minutes.ago.to_i) }

      let(:visit1) do
        {
          start_time: 2.hours.ago.to_i,
          end_time: 1.hour.ago.to_i,
          center_lat: 40.7128,
          center_lon: -74.0060,
          points: [point1]
        }
      end

      # Very close to visit1 center (~15m away), small time gap
      let(:visit2) do
        {
          start_time: 50.minutes.ago.to_i,
          end_time: 40.minutes.ago.to_i,
          center_lat: 40.71290,
          center_lon: -74.00610,
          points: [point2]
        }
      end

      # Far from visit1/visit2 center (~4km away), should not merge
      let(:visit3) do
        {
          start_time: 30.minutes.ago.to_i,
          end_time: 20.minutes.ago.to_i,
          center_lat: 40.7500,
          center_lon: -74.0500,
          points: [double('Point5')]
        }
      end

      let(:visits) { [visit1, visit2, visit3] }

      subject { described_class.new(points) }

      it 'merges consecutive visits that meet criteria' do
        merged = subject.merge_visits(visits)

        expect(merged.size).to eq(2)
        expect(merged.first[:points].size).to eq(2)
        expect(merged.first[:end_time]).to eq(visit2[:end_time])
        expect(merged.last).to eq(visit3)
      end
    end

    context 'when visits cannot be merged' do
      let(:points) { user.points.order(timestamp: :asc) }

      # All visits have centers far apart (>50m threshold)
      let(:visit1) do
        {
          start_time: 2.hours.ago.to_i,
          end_time: 1.hour.ago.to_i,
          center_lat: 40.7128,
          center_lon: -74.0060,
          points: [double('Point1')]
        }
      end

      let(:visit2) do
        {
          start_time: 50.minutes.ago.to_i,
          end_time: 40.minutes.ago.to_i,
          center_lat: 40.7500,
          center_lon: -74.0500,
          points: [double('Point3')]
        }
      end

      let(:visit3) do
        {
          start_time: 30.minutes.ago.to_i,
          end_time: 20.minutes.ago.to_i,
          center_lat: 40.8000,
          center_lon: -74.1000,
          points: [double('Point5')]
        }
      end

      let(:visits) { [visit1, visit2, visit3] }

      subject { described_class.new(points) }

      it 'keeps visits separate' do
        merged = subject.merge_visits(visits)

        expect(merged.size).to eq(3)
        expect(merged).to eq(visits)
      end
    end

    context 'with empty visits array' do
      let(:points) { user.points.order(timestamp: :asc) }

      subject { described_class.new(points) }

      it 'returns an empty array' do
        expect(subject.merge_visits([])).to eq([])
      end
    end
  end

  describe '#traveled_far_during_gap?' do
    let(:base_time) { Time.zone.now }

    let(:first_visit) do
      {
        start_time: (base_time - 2.hours).to_i,
        end_time: (base_time - 1.hour).to_i,
        center_lat: 40.7128,
        center_lon: -74.0060,
        points: []
      }
    end

    let(:second_visit) do
      {
        start_time: (base_time - 30.minutes).to_i,
        end_time: (base_time - 20.minutes).to_i,
        center_lat: 40.7128,
        center_lon: -74.0060,
        points: []
      }
    end

    context 'with minimal travel during gap' do
      before do
        # Points during the gap that don't travel far
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 55.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 50.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0062 40.7130)',
               timestamp: (base_time - 45.minutes).to_i)
      end

      it 'returns false when travel distance is minimal' do
        result = subject.send(:traveled_far_during_gap?, first_visit, second_visit)
        expect(result).to be false
      end
    end

    context 'with significant travel during gap' do
      before do
        # Points that travel far (~1km apart)
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 55.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0160 40.7228)',
               timestamp: (base_time - 50.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0260 40.7328)',
               timestamp: (base_time - 45.minutes).to_i)
      end

      it 'returns true when travel distance exceeds threshold' do
        result = subject.send(:traveled_far_during_gap?, first_visit, second_visit)
        expect(result).to be true
      end
    end

    context 'with no points during gap' do
      it 'returns false' do
        result = subject.send(:traveled_far_during_gap?, first_visit, second_visit)
        expect(result).to be false
      end
    end
  end

  describe '#can_merge_visits? with extended window' do
    let(:base_time) { Time.zone.now }

    let(:first_visit) do
      {
        start_time: (base_time - 3.hours).to_i,
        end_time: (base_time - 2.hours).to_i,
        center_lat: 40.7128,
        center_lon: -74.0060,
        points: []
      }
    end

    context 'with gap within MAXIMUM_VISIT_GAP' do
      let(:second_visit) do
        {
          start_time: (base_time - 90.minutes).to_i,
          end_time: (base_time - 80.minutes).to_i,
          center_lat: 40.7129,
          center_lon: -74.0061,
          points: []
        }
      end

      before do
        allow(subject).to receive(:significant_movement_between?).and_return(false)
      end

      it 'allows merge without travel check' do
        result = subject.send(:can_merge_visits?, first_visit, second_visit)
        expect(result).to be true
      end
    end

    context 'with gap in extended window (30min - 2hr)' do
      let(:second_visit) do
        {
          start_time: (base_time - 60.minutes).to_i,
          end_time: (base_time - 50.minutes).to_i,
          center_lat: 40.7129,
          center_lon: -74.0061,
          points: []
        }
      end

      before do
        allow(subject).to receive(:traveled_far_during_gap?).and_return(false)
      end

      it 'checks travel distance for extended gaps' do
        expect(subject).to receive(:traveled_far_during_gap?)
        subject.send(:can_merge_visits?, first_visit, second_visit)
      end
    end

    context 'with gap beyond EXTENDED_MERGE_WINDOW' do
      let(:second_visit) do
        {
          start_time: (base_time - 30.minutes).to_i,
          end_time: (base_time - 20.minutes).to_i,
          center_lat: 40.7129,
          center_lon: -74.0061,
          points: []
        }
      end

      it 'rejects merge for very large gaps' do
        # Gap is ~1.5 hours which is still within extended window
        # Let's test with a gap > 2 hours
        very_old_visit = {
          start_time: (base_time - 5.hours).to_i,
          end_time: (base_time - 4.hours).to_i,
          center_lat: 40.7129,
          center_lon: -74.0061,
          points: []
        }

        result = subject.send(:can_merge_visits?, very_old_visit, second_visit)
        expect(result).to be false
      end
    end
  end
end
