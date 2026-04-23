# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Yearly::SchedulingJob, type: :job do
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
      end

      it 'schedules jobs for active users' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
          .with(active_user.id, previous_year)
      end

      it 'schedules jobs for trial users' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
          .with(trial_user.id, previous_year)
      end

      it 'does not schedule jobs for inactive users' do
        expect { subject }
          .not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
          .with(inactive_user.id, anything)
      end
    end

    context 'when user has no stats for previous year' do
      let!(:user_without_stats) { create(:user, status: :active) }
      let!(:user_with_stats) { create(:user, status: :active) }

      before do
        create(:stat, user: user_with_stats, year: previous_year, month: 1)
      end

      it 'does not schedule jobs for user without stats' do
        expect { subject }
          .not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
          .with(user_without_stats.id, anything)
      end

      it 'schedules jobs for user with stats' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
          .with(user_with_stats.id, previous_year)
      end
    end

    context 'when user only has stats for current year' do
      let!(:user_current_year_only) { create(:user, status: :active) }

      before do
        create(:stat, user: user_current_year_only, year: Time.current.year, month: 1)
      end

      it 'does not schedule jobs for that user' do
        expect { subject }
          .not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
          .with(user_current_year_only.id, anything)
      end
    end

    context 'when user has the yearly toggle off' do
      let!(:opted_out_user) do
        create(:user, status: :active, settings: { 'yearly_digest_emails_enabled' => false })
      end
      let!(:opted_in_user) { create(:user, status: :active) }

      before do
        create(:stat, user: opted_out_user, year: previous_year, month: 1)
        create(:stat, user: opted_in_user, year: previous_year, month: 1)
      end

      it 'does not schedule jobs for the opted-out user' do
        expect { subject }
          .not_to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
          .with(opted_out_user.id, anything)
      end

      it 'still schedules jobs for opted-in users' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::Yearly::CalculatingJob)
          .with(opted_in_user.id, previous_year)
      end
    end

    it 'does not enqueue EmailSendingJob directly (email chains from CalculatingJob)' do
      create(:user, status: :active).tap do |u|
        create(:stat, user: u, year: Time.current.year - 1, month: 1)
      end
      expect do
        described_class.new.perform
      end.not_to have_enqueued_job(Users::Digests::Yearly::EmailSendingJob)
    end
  end
end
