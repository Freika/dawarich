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
      let(:start_at) { 20.days.ago }
      let(:end_at) { Time.current }

      it 'does not batch' do
        expect(subject).not_to receive(:process_in_batches)
        subject.call
      end
    end

    context 'with range over 31 days' do
      let(:start_at) { 60.days.ago }
      let(:end_at) { Time.current }

      before do
        create(:point, user: user, lonlat: 'POINT(-74.0060 40.7128)',
               timestamp: 30.days.ago.to_i)
        allow(Geocoder).to receive(:search).and_return([])
      end

      it 'processes in batches' do
        expect(subject).to receive(:process_in_batches).and_call_original
        subject.call
      end
    end
  end
end
