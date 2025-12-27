# frozen_string_literal: true

require 'rails_helper'

RSpec.describe YearlyDigests::YearEndSchedulingJob, type: :job do
  describe '#perform' do
    subject { described_class.perform_now }

    let(:previous_year) { Time.current.year - 1 }

    it 'enqueues to the digests queue' do
      expect(described_class.new.queue_name).to eq('digests')
    end

    context 'with users having different statuses' do
      let!(:active_user) { create(:user, status: :active) }
      let!(:trial_user) { create(:user, status: :trial) }
      let!(:inactive_user) { create(:user) }

      before do
        # Force inactive status after any after_commit callbacks
        inactive_user.update_column(:status, 0) # inactive

        create(:stat, user: active_user, year: previous_year, month: 1)
        create(:stat, user: trial_user, year: previous_year, month: 1)
        create(:stat, user: inactive_user, year: previous_year, month: 1)

        allow(YearlyDigests::CalculatingJob).to receive(:perform_later)
        allow(YearlyDigests::EmailSendingJob).to receive(:set).and_return(double(perform_later: nil))
      end

      it 'schedules jobs for active users' do
        subject

        expect(YearlyDigests::CalculatingJob).to have_received(:perform_later)
          .with(active_user.id, previous_year)
      end

      it 'schedules jobs for trial users' do
        subject

        expect(YearlyDigests::CalculatingJob).to have_received(:perform_later)
          .with(trial_user.id, previous_year)
      end

      it 'does not schedule jobs for inactive users' do
        subject

        expect(YearlyDigests::CalculatingJob).not_to have_received(:perform_later)
          .with(inactive_user.id, anything)
      end

      it 'schedules email sending job with delay' do
        email_job_double = double(perform_later: nil)
        allow(YearlyDigests::EmailSendingJob).to receive(:set)
          .with(wait: 30.minutes)
          .and_return(email_job_double)

        subject

        expect(YearlyDigests::EmailSendingJob).to have_received(:set)
          .with(wait: 30.minutes).at_least(:twice)
      end
    end

    context 'when user has no stats for previous year' do
      let!(:user_without_stats) { create(:user, status: :active) }
      let!(:user_with_stats) { create(:user, status: :active) }

      before do
        create(:stat, user: user_with_stats, year: previous_year, month: 1)

        allow(YearlyDigests::CalculatingJob).to receive(:perform_later)
        allow(YearlyDigests::EmailSendingJob).to receive(:set).and_return(double(perform_later: nil))
      end

      it 'does not schedule jobs for user without stats' do
        subject

        expect(YearlyDigests::CalculatingJob).not_to have_received(:perform_later)
          .with(user_without_stats.id, anything)
      end

      it 'schedules jobs for user with stats' do
        subject

        expect(YearlyDigests::CalculatingJob).to have_received(:perform_later)
          .with(user_with_stats.id, previous_year)
      end
    end

    context 'when user only has stats for current year' do
      let!(:user_current_year_only) { create(:user, status: :active) }

      before do
        create(:stat, user: user_current_year_only, year: Time.current.year, month: 1)

        allow(YearlyDigests::CalculatingJob).to receive(:perform_later)
        allow(YearlyDigests::EmailSendingJob).to receive(:set).and_return(double(perform_later: nil))
      end

      it 'does not schedule jobs for that user' do
        subject

        expect(YearlyDigests::CalculatingJob).not_to have_received(:perform_later)
          .with(user_current_year_only.id, anything)
      end
    end
  end
end
