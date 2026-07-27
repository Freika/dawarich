# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::Merger do
  let(:user) { create(:user) }

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

    context 'when consecutive visits are merged' do
      let(:base_time) { Time.zone.local(2024, 5, 1, 10, 0, 0).to_i }
      let(:points) { user.points.order(timestamp: :asc) }

      let(:geodata) do
        { 'type' => 'Feature', 'properties' => { 'type' => 'street', 'name' => 'Nikolaistrasse' } }
      end

      let!(:point_a) do
        create(:point, user: user, timestamp: base_time, geodata: geodata,
                       latitude: 51.3402, longitude: 12.3712, accuracy: 10)
      end

      let!(:point_b) do
        create(:point, user: user, timestamp: base_time + 1200, geodata: geodata,
                       latitude: 51.3404, longitude: 12.3712, accuracy: 10)
      end

      let(:visit_a) do
        {
          start_time: base_time,
          end_time: base_time + 600,
          duration: 600,
          center_lat: 51.3402,
          center_lon: 12.3712,
          radius: 500,
          suggested_name: 'Stale first-cluster name',
          points: [point_a]
        }
      end

      let(:visit_b) do
        {
          start_time: base_time + 1200,
          end_time: base_time + 1800,
          duration: 600,
          center_lat: 51.3404,
          center_lon: 12.3712,
          radius: 500,
          suggested_name: 'Second cluster name',
          points: [point_b]
        }
      end

      subject(:merger) { described_class.new(points) }

      it 'merges the pair into one visit' do
        expect(merger.merge_visits([visit_a, visit_b]).size).to eq(1)
      end

      it 'recomputes duration to span the merged range' do
        merged = merger.merge_visits([visit_a, visit_b]).first

        expect(merged[:duration]).to eq(merged[:end_time] - merged[:start_time])
        expect(merged[:duration]).to eq(1800)
      end

      it 'recomputes the centre from every merged point' do
        merged = merger.merge_visits([visit_a, visit_b]).first

        expect(merged[:center_lat]).to be_within(0.00001).of(51.3403)
        expect(merged[:center_lon]).to be_within(0.00001).of(12.3712)
      end

      it 'recomputes the radius against the new centre' do
        merged = merger.merge_visits([visit_a, visit_b]).first

        expect(merged[:radius]).to eq(15)
      end

      it 'recomputes the suggested name from every merged point' do
        merged = merger.merge_visits([visit_a, visit_b]).first

        expect(merged[:suggested_name]).to be_present
        expect(merged[:suggested_name]).not_to eq('Stale first-cluster name')
      end

      it 'keeps the pre-merge name when the geocoder lookup fails' do
        point_a.update!(geodata: {})
        point_b.update!(geodata: {})
        allow(Geocoder).to receive(:search).and_return([])

        merged = merger.merge_visits([visit_a, visit_b]).first

        expect(merged[:suggested_name]).to eq('Stale first-cluster name')
      end

      it 'finalizes once across a three-visit chain' do
        point_c = create(:point, user: user, timestamp: base_time + 2400, geodata: geodata,
                                 latitude: 51.3406, longitude: 12.3712, accuracy: 10)
        visit_c = {
          start_time: base_time + 2400, end_time: base_time + 3000, duration: 600,
          center_lat: 51.3406, center_lon: 12.3712, radius: 500,
          suggested_name: 'Third cluster name', points: [point_c]
        }

        result = merger.merge_visits([visit_a, visit_b, visit_c])

        expect(result.size).to eq(1)
        expect(result.first[:points].size).to eq(3)
        expect(result.first[:duration]).to eq(3000)
        expect(result.first[:center_lat]).to be_within(0.00001).of(51.3404)
      end

      it 'leaves an unmerged visit untouched' do
        far_visit = visit_b.merge(center_lat: 51.9, start_time: base_time + 99_999,
                                  end_time: base_time + 100_599)

        result = merger.merge_visits([visit_a, far_visit])

        expect(result.last[:suggested_name]).to eq('Second cluster name')
        expect(result.last[:radius]).to eq(500)
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
end
