# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::DbscanClusterer do
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
  end
end
