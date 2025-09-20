# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkStatsCalculatingJob, type: :job do
  describe '#perform' do
    let(:timestamp) { DateTime.new(2024, 1, 1).to_i }

    context 'with active users' do
      let!(:active_user1) { create(:user, status: :active) }
      let!(:active_user2) { create(:user, status: :active) }

      let!(:points1) do
        (1..10).map do |i|
          create(:point, user_id: active_user1.id, timestamp: timestamp + i.minutes)
        end
      end

      let!(:points2) do
        (1..10).map do |i|
          create(:point, user_id: active_user2.id, timestamp: timestamp + i.minutes)
        end
      end

      before do
        allow(Stats::BulkCalculator).to receive(:new).and_call_original
        allow_any_instance_of(Stats::BulkCalculator).to receive(:call)
      end

      it 'processes all active users' do
        BulkStatsCalculatingJob.perform_now

        expect(Stats::BulkCalculator).to have_received(:new).with(active_user1.id)
        expect(Stats::BulkCalculator).to have_received(:new).with(active_user2.id)
      end

      it 'calls Stats::BulkCalculator for each active user' do
        calculator1 = instance_double(Stats::BulkCalculator)
        calculator2 = instance_double(Stats::BulkCalculator)

        allow(Stats::BulkCalculator).to receive(:new).with(active_user1.id).and_return(calculator1)
        allow(Stats::BulkCalculator).to receive(:new).with(active_user2.id).and_return(calculator2)
        allow(calculator1).to receive(:call)
        allow(calculator2).to receive(:call)

        BulkStatsCalculatingJob.perform_now

        expect(calculator1).to have_received(:call)
        expect(calculator2).to have_received(:call)
      end
    end

    context 'with trial users' do
      let!(:trial_user1) { create(:user, status: :trial) }
      let!(:trial_user2) { create(:user, status: :trial) }

      let!(:points1) do
        (1..5).map do |i|
          create(:point, user_id: trial_user1.id, timestamp: timestamp + i.minutes)
        end
      end

      let!(:points2) do
        (1..5).map do |i|
          create(:point, user_id: trial_user2.id, timestamp: timestamp + i.minutes)
        end
      end

      before do
        allow(Stats::BulkCalculator).to receive(:new).and_call_original
        allow_any_instance_of(Stats::BulkCalculator).to receive(:call)
      end

      it 'processes all trial users' do
        BulkStatsCalculatingJob.perform_now

        expect(Stats::BulkCalculator).to have_received(:new).with(trial_user1.id)
        expect(Stats::BulkCalculator).to have_received(:new).with(trial_user2.id)
      end

      it 'calls Stats::BulkCalculator for each trial user' do
        calculator1 = instance_double(Stats::BulkCalculator)
        calculator2 = instance_double(Stats::BulkCalculator)

        allow(Stats::BulkCalculator).to receive(:new).with(trial_user1.id).and_return(calculator1)
        allow(Stats::BulkCalculator).to receive(:new).with(trial_user2.id).and_return(calculator2)
        allow(calculator1).to receive(:call)
        allow(calculator2).to receive(:call)

        BulkStatsCalculatingJob.perform_now

        expect(calculator1).to have_received(:call)
        expect(calculator2).to have_received(:call)
      end
    end

    context 'with inactive users only' do
      before do
        allow(User).to receive(:active).and_return(User.none)
        allow(User).to receive(:trial).and_return(User.none)
        allow(Stats::BulkCalculator).to receive(:new)
      end

      it 'does not process any users when no active or trial users exist' do
        BulkStatsCalculatingJob.perform_now

        expect(Stats::BulkCalculator).not_to have_received(:new)
      end

      it 'queries for active and trial users but finds none' do
        BulkStatsCalculatingJob.perform_now

        expect(User).to have_received(:active)
        expect(User).to have_received(:trial)
      end
    end

    context 'with mixed user types' do
      let(:active_user) { create(:user, status: :active) }
      let(:trial_user) { create(:user, status: :trial) }
      let(:inactive_user) { create(:user, status: :inactive) }

      before do
        active_users_relation = double('ActiveRecord::Relation')
        trial_users_relation = double('ActiveRecord::Relation')

        allow(active_users_relation).to receive(:pluck).with(:id).and_return([active_user.id])
        allow(trial_users_relation).to receive(:pluck).with(:id).and_return([trial_user.id])

        allow(User).to receive(:active).and_return(active_users_relation)
        allow(User).to receive(:trial).and_return(trial_users_relation)

        allow(Stats::BulkCalculator).to receive(:new).and_call_original
        allow_any_instance_of(Stats::BulkCalculator).to receive(:call)
      end

      it 'processes only active and trial users, skipping inactive users' do
        BulkStatsCalculatingJob.perform_now

        expect(Stats::BulkCalculator).to have_received(:new).with(active_user.id)
        expect(Stats::BulkCalculator).to have_received(:new).with(trial_user.id)
        expect(Stats::BulkCalculator).not_to have_received(:new).with(inactive_user.id)
      end

      it 'processes exactly 2 users (active and trial)' do
        BulkStatsCalculatingJob.perform_now

        expect(Stats::BulkCalculator).to have_received(:new).exactly(2).times
      end
    end
  end
end
