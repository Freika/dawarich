# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::YearEndSchedulingJob, type: :job do
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
          .to have_enqueued_job(Users::Digests::CalculatingJob)
          .with(active_user.id, previous_year)
      end

      it 'schedules jobs for trial users' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::CalculatingJob)
          .with(trial_user.id, previous_year)
      end

      it 'does not schedule jobs for inactive users' do
        expect { subject }
          .not_to have_enqueued_job(Users::Digests::CalculatingJob)
          .with(inactive_user.id, anything)
      end

      it 'schedules email sending job with delay' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::EmailSendingJob).at_least(:twice)
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
          .not_to have_enqueued_job(Users::Digests::CalculatingJob)
          .with(user_without_stats.id, anything)
      end

      it 'schedules jobs for user with stats' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::CalculatingJob)
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
          .not_to have_enqueued_job(Users::Digests::CalculatingJob)
          .with(user_current_year_only.id, anything)
      end
    end
  end
end
