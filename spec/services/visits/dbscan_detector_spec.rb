# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::DbscanDetector do
  let(:user) { create(:user) }
  let(:base_time) { Time.zone.now }
  let(:start_at) { base_time - 2.hours }
  let(:end_at) { base_time }

  subject { described_class.new(points_relation, user: user, start_at: start_at, end_at: end_at) }

  let(:points_relation) { user.points.where(timestamp: start_at.to_i..end_at.to_i) }

  before do
    allow(Visits::Names::Suggester).to receive(:new).and_return(double(call: 'Test Place'))
    allow(Visits::Names::Fetcher).to receive(:new).and_return(double(call: 'Fetched Place'))
  end

  describe '#call' do
    context 'with clusterable points' do
      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 90.minutes).to_i, accuracy: 10)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 80.minutes).to_i, accuracy: 10)
        create(:point, user: user, lonlat: 'POINT(-74.0062 40.7130)',
               timestamp: (base_time - 70.minutes).to_i, accuracy: 10)
      end

      it 'returns visit hashes with expected structure' do
        result = subject.call

        expect(result).to be_an(Array)
        expect(result).not_to be_empty
        visit = result.first

        expect(visit).to include(
          :start_time, :end_time, :duration,
          :center_lat, :center_lon, :radius,
          :points, :suggested_name
        )
      end

      it 'calculates duration from start and end times' do
        result = subject.call
        visit = result.first

        expect(visit[:duration]).to eq(visit[:end_time] - visit[:start_time])
      end

      it 'includes point objects in the visit' do
        result = subject.call
        visit = result.first

        expect(visit[:points]).to all(be_a(Point))
        expect(visit[:points].size).to be >= 2
      end

      it 'sorts points by timestamp' do
        result = subject.call
        timestamps = result.first[:points].map(&:timestamp)

        expect(timestamps).to eq(timestamps.sort)
      end
    end

    context 'when no clusters are found' do
      before do
        # Widely spaced points that won't cluster
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 90.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-75.0000 41.0000)',
               timestamp: (base_time - 80.minutes).to_i)
      end

      it 'returns an empty array' do
        result = subject.call

        expect(result).to eq([])
      end
    end

    context 'when DBSCAN query fails (timeout)' do
      before do
        allow(Visits::DbscanClusterer).to receive(:new).and_return(double(call: nil))
      end

      it 'returns nil to signal fallback' do
        result = subject.call

        expect(result).to be_nil
      end
    end

    context 'when point lookup fails with StatementInvalid' do
      before do
        clusters = [{ point_ids: [999_999], start_time: start_at.to_i, end_time: end_at.to_i, point_count: 1 }]
        allow(Visits::DbscanClusterer).to receive(:new).and_return(double(call: clusters))
        allow(Point).to receive(:where).and_raise(ActiveRecord::StatementInvalid, 'connection lost')
      end

      it 'returns nil' do
        result = subject.call

        expect(result).to be_nil
      end
    end

    context 'with synthetic negative IDs from density normalization' do
      let(:user) do
        create(:user, settings: {
                 'density_normalization_enabled' => true,
                 'route_opacity' => 60,
                 'meters_between_routes' => '500',
                 'minutes_between_routes' => '30',
                 'fog_of_war_meters' => '100',
                 'time_threshold_minutes' => '30',
                 'merge_threshold_minutes' => '15'
               })
      end
      let(:start_at) { base_time - 3.hours }

      before do
        # Cluster with a 45-minute gap at the same location to trigger synthetic points
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 170.minutes).to_i, accuracy: 10)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 160.minutes).to_i, accuracy: 10)
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 115.minutes).to_i, accuracy: 10)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 105.minutes).to_i, accuracy: 10)
      end

      it 'only includes real points in the visit (no synthetic negative IDs)' do
        result = subject.call

        expect(result).not_to be_empty
        result.each do |visit|
          visit[:points].each do |point|
            expect(point.id).to be_positive
          end
        end
      end
    end

    context 'when some point IDs from cluster no longer exist in DB' do
      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 90.minutes).to_i, accuracy: 10)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 80.minutes).to_i, accuracy: 10)
        create(:point, user: user, lonlat: 'POINT(-74.0062 40.7130)',
               timestamp: (base_time - 70.minutes).to_i, accuracy: 10)
      end

      it 'skips missing points without error' do
        real_ids = user.points.pluck(:id)
        # Inject a non-existent ID into the cluster results
        fake_clusters = [{
          point_ids: real_ids + [999_999_999],
          start_time: (base_time - 90.minutes).to_i,
          end_time: (base_time - 70.minutes).to_i,
          point_count: real_ids.size + 1
        }]
        allow(Visits::DbscanClusterer).to receive(:new).and_return(double(call: fake_clusters))

        result = subject.call

        expect(result).not_to be_empty
        expect(result.first[:points].size).to eq(real_ids.size)
      end
    end

    context 'with accuracy-weighted center calculation' do
      before do
        # High-accuracy point at one position
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 90.minutes).to_i, accuracy: 5)
        # Low-accuracy point at a slightly different position
        create(:point, user: user, lonlat: 'POINT(-74.0070 40.7138)',
               timestamp: (base_time - 80.minutes).to_i, accuracy: 100)
        # Another high-accuracy point at the first position
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 70.minutes).to_i, accuracy: 5)
      end

      it 'weights center toward high-accuracy points' do
        result = subject.call

        expect(result).not_to be_empty
        visit = result.first

        # Center should be closer to 40.7128/-74.0060 (high accuracy) than 40.7138/-74.0070 (low accuracy)
        expect(visit[:center_lat]).to be_within(0.001).of(40.7128)
        expect(visit[:center_lon]).to be_within(0.001).of(-74.0060)
      end
    end

    context 'when cluster points are all missing from DB' do
      before do
        fake_clusters = [{
          point_ids: [999_999_998, 999_999_999],
          start_time: (base_time - 90.minutes).to_i,
          end_time: (base_time - 70.minutes).to_i,
          point_count: 2
        }]
        allow(Visits::DbscanClusterer).to receive(:new).and_return(double(call: fake_clusters))
      end

      it 'skips the cluster and returns empty array' do
        result = subject.call

        expect(result).to eq([])
      end
    end
  end
end
