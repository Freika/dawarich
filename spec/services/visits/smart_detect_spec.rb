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

    context 'when there are points' do
      let(:visit_detector) { instance_double(Visits::Detector) }
      let(:visit_merger) { instance_double(Visits::Merger) }
      let(:visit_creator) { instance_double(Visits::Creator) }
      let(:potential_visits) { [{ id: 1, center_lat: 40.7128, center_lon: -74.0060 }] }
      let(:merged_visits) { [{ id: 2, center_lat: 40.7128, center_lon: -74.0060 }] }
      let(:created_visits) { [instance_double(Visit)] }

      before do
        allow(user).to receive_message_chain(:points, :not_visited, :order, :where).and_return(points)
        allow(Visits::Detector).to receive(:new).with(
          points,
          user: user,
          start_at: start_at.to_i,
          end_at: end_at.to_i
        ).and_return(visit_detector)
        allow(Visits::Merger).to receive(:new).with(points, user: user).and_return(visit_merger)
        allow(Visits::Creator).to receive(:new).with(user).and_return(visit_creator)
        allow(visit_detector).to receive(:detect_potential_visits).and_return(potential_visits)
        allow(visit_merger).to receive(:merge_visits).with(potential_visits).and_return(merged_visits)
        allow(visit_creator).to receive(:create_visits).with(merged_visits).and_return(created_visits)
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
        allow_any_instance_of(Visits::DbscanClusterer).to receive(:call)
          .and_raise(ActiveRecord::StatementInvalid, 'canceling statement due to statement timeout')

        # Create points that form a valid visit for the fallback iteration path
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
    describe '#should_batch?' do
      context 'with range under 31 days' do
        let(:start_at) { 20.days.ago }
        let(:end_at) { Time.current }

        it 'does not batch' do
          # Uses process_single_range, not process_in_batches
          expect(subject).not_to receive(:process_in_batches)
          subject.call
        end
      end

      context 'with range over 31 days' do
        let(:start_at) { 60.days.ago }
        let(:end_at) { Time.current }

        before do
          # Need at least one unvisited point so the early return doesn't fire
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

  describe 'constants' do
    it 'has expected values' do
      expect(described_class::BATCH_THRESHOLD_DAYS).to eq(31)
      expect(described_class::BATCH_OVERLAP_SECONDS).to eq(1.hour.to_i)
    end
  end
end
