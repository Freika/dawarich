# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkVisitsSuggestingJob, type: :job do
  describe '#perform' do
    let(:start_at) { 1.day.ago.beginning_of_day }
    let(:end_at) { 1.day.ago.end_of_day }
    let(:user) { create(:user) }
    let(:inactive_user) { create(:user, :inactive) }
    let(:user_with_points) { create(:user) }
    let(:time_chunks) { [[start_at, end_at]] }

    before do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(true)
      allow_any_instance_of(Visits::TimeChunks).to receive(:call).and_return(time_chunks)
      create(:point, user: user_with_points)
    end

    it 'does nothing if reverse geocoding is disabled' do
      allow(DawarichSettings).to receive(:reverse_geocoding_enabled?).and_return(false)

      expect(VisitSuggestingJob).not_to receive(:perform_later)

      described_class.perform_now
    end

    it 'schedules jobs only for active users with tracked points' do
      expect(VisitSuggestingJob).to receive(:perform_later).with(
        user_id: user_with_points.id,
        start_at: time_chunks.first.first,
        end_at: time_chunks.first.last
      )

      expect(VisitSuggestingJob).not_to receive(:perform_later).with(
        user_id: user.id,
        start_at: anything,
        end_at: anything
      )

      expect(VisitSuggestingJob).not_to receive(:perform_later).with(
        user_id: inactive_user.id,
        start_at: anything,
        end_at: anything
      )

      described_class.perform_now
    end

    it 'handles multiple time chunks' do
      chunks = [
        [start_at, start_at + 12.hours],
        [start_at + 12.hours, end_at]
      ]
      allow_any_instance_of(Visits::TimeChunks).to receive(:call).and_return(chunks)

      active_users_mock = double('ActiveRecord::Relation')
      allow(User).to receive(:active).and_return(active_users_mock)
      allow(active_users_mock).to receive(:active).and_return(active_users_mock)
      allow(active_users_mock).to receive(:where).with(id: []).and_return(active_users_mock)
      allow(active_users_mock).to receive(:find_each).and_yield(user_with_points)

      chunks.each do |chunk|
        expect(VisitSuggestingJob).to receive(:perform_later).with(
          user_id: user_with_points.id,
          start_at: chunk.first,
          end_at: chunk.last
        )
      end

      described_class.perform_now
    end

    it 'only processes specified users when user_ids is provided' do
      create(:point, user: user)

      expect(VisitSuggestingJob).to receive(:perform_later).with(
        user_id: user.id,
        start_at: time_chunks.first.first,
        end_at: time_chunks.first.last
      )

      expect(VisitSuggestingJob).not_to receive(:perform_later).with(
        user_id: user_with_points.id,
        start_at: anything,
        end_at: anything
      )

      described_class.perform_now(user_ids: [user.id])
    end

    it 'uses custom time range when provided' do
      custom_start = 2.days.ago.beginning_of_day
      custom_end = 2.days.ago.end_of_day
      custom_chunks = [[custom_start, custom_end]]

      time_chunks_instance = instance_double(Visits::TimeChunks)
      allow(Visits::TimeChunks).to receive(:new)
        .with(start_at: custom_start, end_at: custom_end)
        .and_return(time_chunks_instance)
      allow(time_chunks_instance).to receive(:call).and_return(custom_chunks)

      active_users_mock = double('ActiveRecord::Relation')
      allow(User).to receive(:active).and_return(active_users_mock)
      allow(active_users_mock).to receive(:active).and_return(active_users_mock)
      allow(active_users_mock).to receive(:where).with(id: []).and_return(active_users_mock)
      allow(active_users_mock).to receive(:find_each).and_yield(user_with_points)

      expect(VisitSuggestingJob).to receive(:perform_later).with(
        user_id: user_with_points.id,
        start_at: custom_chunks.first.first,
        end_at: custom_chunks.first.last
      )

      described_class.perform_now(start_at: custom_start, end_at: custom_end)
    end

    context 'when visits suggestions are disabled' do
      before do
        allow_any_instance_of(Users::SafeSettings).to receive(:visits_suggestions_enabled?).and_return(false)
      end

      it 'does not schedule jobs' do
        expect(VisitSuggestingJob).not_to receive(:perform_later)

        described_class.perform_now
      end
    end
  end
end
