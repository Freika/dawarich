# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::DbscanClusterer do
  let(:user_settings) do
    {
      'route_opacity' => 60,
      'meters_between_routes' => '500',
      'minutes_between_routes' => '30',
      'fog_of_war_meters' => '100',
      'time_threshold_minutes' => '30',
      'merge_threshold_minutes' => '15',
      'maps' => { 'distance_unit' => 'km' }
    }
  end
  let(:user) { create(:user) }
  let(:base_time) { Time.zone.now }

  subject { described_class.new(user, start_at: start_at, end_at: end_at) }

  let(:start_at) { base_time - 2.hours }
  let(:end_at) { base_time }

  describe '#call' do
    context 'with clusterable points' do
      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 90.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 80.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0062 40.7130)', timestamp: (base_time - 70.minutes).to_i)
      end

      it 'returns clusters with expected structure' do
        result = subject.call

        expect(result).to be_an(Array)
        expect(result.first).to include(
          :visit_id,
          :point_ids,
          :start_time,
          :end_time,
          :point_count
        )
      end

      it 'identifies a cluster from nearby points' do
        result = subject.call

        expect(result.size).to be >= 1
        cluster = result.first
        expect(cluster[:point_ids].size).to be >= 2
        expect(cluster[:point_count]).to be >= 2
      end
    end

    context 'with points spread apart spatially' do
      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 90.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-75.0000 41.0000)', timestamp: (base_time - 80.minutes).to_i)
      end

      it 'does not create clusters from widely spaced points' do
        result = subject.call

        expect(result).to be_empty
      end
    end

    context 'with time gap larger than threshold' do
      let(:user) { create(:user, settings: user_settings.merge('density_normalization_enabled' => false)) }

      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 90.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 80.minutes).to_i)

        # Same location but 40 minutes later (beyond time gap threshold)
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 30.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 20.minutes).to_i)
      end

      it 'splits clusters on time gaps' do
        result = subject.call

        expect(result.size).to eq(2)
      end
    end

    context 'with visits too short in duration' do
      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 90.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 89.minutes).to_i)
      end

      it 'filters out short duration clusters' do
        result = subject.call

        expect(result).to be_empty
      end
    end

    context 'with no unvisited points' do
      before do
        visit = create(:visit, user: user)
        create(:point, user: user, visit: visit, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 90.minutes).to_i)
      end

      it 'returns empty array' do
        result = subject.call

        expect(result).to be_empty
      end
    end

    context 'with points at extreme latitude (near pole)' do
      let(:user) { create(:user, settings: user_settings.merge('density_normalization_enabled' => false)) }

      before do
        create(:point, user: user, lonlat: 'POINT(25.0 89.5)', timestamp: (base_time - 90.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(25.001 89.5)', timestamp: (base_time - 80.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(25.002 89.5)', timestamp: (base_time - 70.minutes).to_i)
      end

      it 'clusters points correctly at extreme latitudes' do
        result = subject.call

        expect(result.size).to eq(1)
        expect(result.first[:point_count]).to eq(3)
      end
    end

    context 'with points outside the time range' do
      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 5.hours).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 4.hours).to_i)
      end

      it 'does not include points outside range' do
        result = subject.call

        expect(result).to be_empty
      end
    end

    context 'with density normalization enabled and a gap at the same location' do
      let(:start_at) { base_time - 3.hours }
      let(:user) { create(:user, settings: user_settings.merge('density_normalization_enabled' => true)) }

      before do
        # Cluster 1: two points at location
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 170.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 160.minutes).to_i)

        # 45-minute GPS gap (phone off at restaurant)

        # Cluster 2: two points at same location after the gap
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 115.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 105.minutes).to_i)
      end

      it 'bridges the gap with synthetic points and produces one cluster' do
        result = subject.call

        expect(result.size).to eq(1)
        expect(result.first[:start_time]).to eq((base_time - 170.minutes).to_i)
        expect(result.first[:end_time]).to eq((base_time - 105.minutes).to_i)
      end

      it 'includes negative synthetic IDs in point_ids' do
        result = subject.call
        point_ids = result.first[:point_ids]

        real_ids = point_ids.select(&:positive?)
        synthetic_ids = point_ids.select(&:negative?)

        expect(real_ids.size).to eq(4)
        expect(synthetic_ids).not_to be_empty
      end
    end

    context 'with density normalization disabled and a gap at the same location' do
      let(:start_at) { base_time - 3.hours }
      let(:user) { create(:user, settings: user_settings.merge('density_normalization_enabled' => false)) }

      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 170.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 160.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 115.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 105.minutes).to_i)
      end

      it 'produces two separate clusters without synthetic points' do
        result = subject.call

        expect(result.size).to eq(2)
        all_ids = result.flat_map { |c| c[:point_ids] }
        expect(all_ids).to all(be_positive)
      end
    end

    context 'with gap exceeding max gap minutes' do
      let(:start_at) { base_time - 15.hours }
      let(:user) { create(:user, settings: user_settings.merge('density_normalization_enabled' => true)) }

      before do
        # Within-cluster points < 60s apart (no synthetic fill within clusters)
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 14.hours).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 14.hours + 30.seconds).to_i)

        # 13-hour gap — exceeds default density_max_gap_minutes (720 min = 12 hours)

        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 10.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 10.minutes + 30.seconds).to_i)
      end

      it 'does not generate synthetic points for gaps exceeding max' do
        result = subject.call

        all_ids = result.flat_map { |c| c[:point_ids] }
        expect(all_ids).to all(be_positive)
      end
    end

    context 'with gap between distant points' do
      let(:start_at) { base_time - 3.hours }
      let(:user) { create(:user, settings: user_settings.merge('density_normalization_enabled' => true)) }

      before do
        # Within-cluster points < 60s apart (no synthetic fill within clusters)
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)', timestamp: (base_time - 170.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)', timestamp: (base_time - 170.minutes + 30.seconds).to_i)

        # 45-minute gap, but endpoint is 500m+ away — exceeds density_max_distance_meters
        create(:point, user: user, lonlat: 'POINT(-74.0120 40.7180)', timestamp: (base_time - 115.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0121 40.7181)', timestamp: (base_time - 115.minutes + 30.seconds).to_i)
      end

      it 'does not generate synthetic points when distance exceeds threshold' do
        result = subject.call

        all_ids = result.flat_map { |c| c[:point_ids] }
        expect(all_ids).to all(be_positive)
      end
    end
  end
end
