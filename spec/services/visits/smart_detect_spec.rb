# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Visits::SmartDetect do
  let(:user) { create(:user) }
  let(:start_at) { 1.day.ago }
  let(:end_at) { Time.current }

  subject { described_class.new(user, start_at: start_at, end_at: end_at) }

  describe '#call' do
    context 'when there are no points' do
      it 'returns an empty array' do
        expect(subject.call).to eq([])
      end
    end

    context 'when there are points that form a visit' do
      let(:base_time) { Time.zone.now }
      let(:start_at) { base_time - 2.hours }
      let(:end_at) { base_time }

      before do
        allow(Geocoder).to receive(:search).and_return([])

        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 90.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 80.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0062 40.7130)',
               timestamp: (base_time - 70.minutes).to_i)
      end

      it 'creates visits from detected clusters' do
        expect { subject.call }.to change(Visit, :count).by_at_least(1)
      end
    end

    context 'when DBSCAN fails and falls back to iteration' do
      let(:base_time) { Time.zone.now }
      let(:start_at) { base_time - 2.hours }
      let(:end_at) { base_time }

      before do
        allow(Geocoder).to receive(:search).and_return([])
        allow(Visits::DbscanClusterer).to receive(:new)
          .and_raise(ActiveRecord::StatementInvalid, 'canceling statement due to statement timeout')

        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 90.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 80.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0062 40.7130)',
               timestamp: (base_time - 70.minutes).to_i)
      end

      it 'still creates visits via iteration fallback' do
        expect { subject.call }.to change(Visit, :count).by_at_least(1)
      end
    end
  end

  describe 'monthly batching' do
    context 'with range under 31 days' do
      let(:base_time) { Time.zone.now }
      let(:start_at) { base_time - 20.days }
      let(:end_at) { base_time }

      before do
        allow(Geocoder).to receive(:search).and_return([])

        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 10.days).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 10.days + 10.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0062 40.7130)',
               timestamp: (base_time - 10.days + 20.minutes).to_i)
      end

      it 'creates visits from data within a single range' do
        expect { subject.call }.to change(Visit, :count).by_at_least(1)
      end
    end

    context 'with range over 31 days' do
      let(:base_time) { Time.zone.now }
      let(:start_at) { base_time - 60.days }
      let(:end_at) { base_time }

      before do
        allow(Geocoder).to receive(:search).and_return([])

        # Points in the first month
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: (base_time - 50.days).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0061 40.7129)',
               timestamp: (base_time - 50.days + 10.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-74.0062 40.7130)',
               timestamp: (base_time - 50.days + 20.minutes).to_i)

        # Points in a later month
        create(:point, user: user, lonlat: 'POINT(-73.9800 40.7600)',
               timestamp: (base_time - 10.days).to_i)
        create(:point, user: user, lonlat: 'POINT(-73.9801 40.7601)',
               timestamp: (base_time - 10.days + 10.minutes).to_i)
        create(:point, user: user, lonlat: 'POINT(-73.9802 40.7602)',
               timestamp: (base_time - 10.days + 20.minutes).to_i)
      end

      it 'creates visits from data spread across months' do
        expect { subject.call }.to change(Visit, :count).by_at_least(2)
      end
    end
  end
end
