# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tracks::BulkCreatingJob, type: :job do
  describe '#perform' do
    let!(:active_user) { create(:user) }
    let!(:inactive_user) { create(:user, :inactive) }
    let!(:user_without_points) { create(:user) }

    let(:start_at) { 1.day.ago.beginning_of_day }
    let(:end_at) { 1.day.ago.end_of_day }

    before do
      # Create points for active user in the target timeframe
      create(:point, user: active_user, timestamp: start_at.to_i + 1.hour.to_i)
      create(:point, user: active_user, timestamp: start_at.to_i + 2.hours.to_i)

      # Create points for inactive user in the target timeframe
      create(:point, user: inactive_user, timestamp: start_at.to_i + 1.hour.to_i)
    end

    it 'schedules tracks creation jobs for active users with points in the timeframe' do
      expect {
        described_class.new.perform(start_at: start_at, end_at: end_at)
      }.to have_enqueued_job(Tracks::CreateJob).with(active_user.id, start_at: start_at, end_at: end_at, cleaning_strategy: :daily)
    end

    it 'does not schedule jobs for users without tracked points' do
      expect {
        described_class.new.perform(start_at: start_at, end_at: end_at)
      }.not_to have_enqueued_job(Tracks::CreateJob).with(user_without_points.id, start_at: start_at, end_at: end_at, cleaning_strategy: :daily)
    end

    it 'does not schedule jobs for users without points in the specified timeframe' do
      # Create a user with points outside the timeframe
      user_with_old_points = create(:user)
      create(:point, user: user_with_old_points, timestamp: 2.days.ago.to_i)

      expect {
        described_class.new.perform(start_at: start_at, end_at: end_at)
      }.not_to have_enqueued_job(Tracks::CreateJob).with(user_with_old_points.id, start_at: start_at, end_at: end_at, cleaning_strategy: :daily)
    end

    context 'when specific user_ids are provided' do
      it 'only processes the specified users' do
        expect {
          described_class.new.perform(start_at: start_at, end_at: end_at, user_ids: [active_user.id])
        }.to have_enqueued_job(Tracks::CreateJob).with(active_user.id, start_at: start_at, end_at: end_at, cleaning_strategy: :daily)
      end

      it 'does not process users not in the user_ids list' do
        expect {
          described_class.new.perform(start_at: start_at, end_at: end_at, user_ids: [active_user.id])
        }.not_to have_enqueued_job(Tracks::CreateJob).with(inactive_user.id, start_at: start_at, end_at: end_at, cleaning_strategy: :daily)
      end
    end

    context 'with default parameters' do
      it 'uses yesterday as the default timeframe' do
        expect {
          described_class.new.perform
        }.to have_enqueued_job(Tracks::CreateJob).with(
          active_user.id,
          start_at: 1.day.ago.beginning_of_day.to_datetime,
          end_at: 1.day.ago.end_of_day.to_datetime,
          cleaning_strategy: :daily
        )
      end
    end
  end
end
