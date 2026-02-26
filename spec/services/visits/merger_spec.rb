# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Merger do
  let(:user) { create(:user) }
  let(:base_time) { Time.zone.now }
  let(:points) { user.points }

  subject { described_class.new(points, user: user) }

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

      subject { described_class.new(points) }

      it 'keeps them separate' do
        merged = subject.merge_visits([visit1, visit2])

        expect(merged.size).to eq(2)
      end
    end

    context 'with empty visits array' do
      let(:points) { user.points.order(timestamp: :asc) }

      subject { described_class.new(points) }

      it 'returns an empty array' do
        expect(subject.merge_visits([])).to eq([])
      end
    end

    context 'with extended merge window and minimal travel' do
      # Gap of 1 hour — beyond MAXIMUM_VISIT_GAP (30min) but within
      # extended merge window (2 hours). User stayed nearby.
      let(:visit1) do
        {
          start_time: (base_time - 3.hours).to_i,
          end_time: (base_time - 2.hours).to_i,
          center_lat: 40.7128,
          center_lon: -74.0060,
          points: [double('Point1')]
        }
      end

      let(:visit2) do
        {
          start_time: (base_time - 60.minutes).to_i,
          end_time: (base_time - 50.minutes).to_i,
          center_lat: 40.7129,
          center_lon: -74.0061,
          points: [double('Point2')]
        }
      end

      before do
        # Points during the gap that don't travel far (nearby)
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 110.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 100.minutes).to_i)
      end

      it 'merges visits when travel during gap is minimal' do
        merged = subject.merge_visits([visit1, visit2])

        expect(merged.size).to eq(1)
      end
    end

    context 'with extended merge window and significant travel' do
      let(:visit1) do
        {
          start_time: (base_time - 3.hours).to_i,
          end_time: (base_time - 2.hours).to_i,
          center_lat: 40.7128,
          center_lon: -74.0060,
          points: [double('Point1')]
        }
      end

      let(:visit2) do
        {
          start_time: (base_time - 60.minutes).to_i,
          end_time: (base_time - 50.minutes).to_i,
          center_lat: 40.7129,
          center_lon: -74.0061,
          points: [double('Point2')]
        }
      end

      before do
        # Points during the gap that travel far (~1km apart)
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 110.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0160 40.7228)',
               timestamp: (base_time - 100.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0260 40.7328)',
               timestamp: (base_time - 90.minutes).to_i)
      end

      it 'does not merge visits when travel is significant' do
        merged = subject.merge_visits([visit1, visit2])

        expect(merged.size).to eq(2)
      end
    end

    context 'with gap beyond extended merge window' do
      let(:visit1) do
        {
          start_time: (base_time - 5.hours).to_i,
          end_time: (base_time - 4.hours).to_i,
          center_lat: 40.7128,
          center_lon: -74.0060,
          points: [double('Point1')]
        }
      end

      let(:visit2) do
        {
          start_time: (base_time - 30.minutes).to_i,
          end_time: (base_time - 20.minutes).to_i,
          center_lat: 40.7129,
          center_lon: -74.0061,
          points: [double('Point2')]
        }
      end

      it 'does not merge visits' do
        merged = subject.merge_visits([visit1, visit2])

        expect(merged.size).to eq(2)
      end
    end
  end
end
