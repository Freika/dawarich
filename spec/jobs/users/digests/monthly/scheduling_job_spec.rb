# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::Monthly::SchedulingJob, type: :job do
  describe '#perform' do
    subject { described_class.perform_now }

    let(:target_year)  { 1.month.ago.year }
    let(:target_month) { 1.month.ago.month }

    it 'enqueues to the digests queue' do
      expect(described_class.new.queue_name).to eq('digests')
    end

    context 'with users having different statuses' do
      let!(:active_user) { create(:user, status: :active, settings: { 'monthly_digest_emails_enabled' => true }) }
      let!(:trial_user)  { create(:user, status: :trial,  settings: { 'monthly_digest_emails_enabled' => true }) }
      let!(:inactive_user) { create(:user, settings: { 'monthly_digest_emails_enabled' => true }) }

      before do
        inactive_user.update_column(:status, 0) # force inactive

        create(:stat, user: active_user, year: target_year, month: target_month)
        create(:stat, user: trial_user,  year: target_year, month: target_month)
        create(:stat, user: inactive_user, year: target_year, month: target_month)
      end

      it 'schedules jobs for active users' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::Monthly::CalculatingJob)
          .with(active_user.id, target_year, target_month)
      end

      it 'schedules jobs for trial users' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::Monthly::CalculatingJob)
          .with(trial_user.id, target_year, target_month)
      end

      it 'does not schedule jobs for inactive users' do
        expect { subject }
          .not_to have_enqueued_job(Users::Digests::Monthly::CalculatingJob)
          .with(inactive_user.id, anything)
      end
    end

    context 'when user has digest toggle off' do
      let!(:user) { create(:user, status: :active, settings: { 'monthly_digest_emails_enabled' => false }) }

      before do
        create(:stat, user: user, year: target_year, month: target_month)
      end

      it 'skips users with the toggle off' do
        expect { subject }
          .not_to have_enqueued_job(Users::Digests::Monthly::CalculatingJob)
      end
    end

    context 'when user has no stats for the target period' do
      let!(:user_without_stats) do
        create(:user, status: :active, settings: { 'monthly_digest_emails_enabled' => true })
      end
      let!(:user_with_stats) do
        create(:user, status: :active, settings: { 'monthly_digest_emails_enabled' => true })
      end

      before do
        create(:stat, user: user_with_stats, year: target_year, month: target_month)
      end

      it 'does not schedule jobs for user without stats' do
        expect { subject }
          .not_to have_enqueued_job(Users::Digests::Monthly::CalculatingJob)
          .with(user_without_stats.id, anything)
      end

      it 'schedules jobs for user with stats' do
        expect { subject }
          .to have_enqueued_job(Users::Digests::Monthly::CalculatingJob)
          .with(user_with_stats.id, target_year, target_month)
      end
    end

    it 'never enqueues the email sending job directly' do
      user = create(:user, status: :active, settings: { 'monthly_digest_emails_enabled' => true })
      create(:stat, user: user, year: target_year, month: target_month)

      expect { subject }
        .not_to have_enqueued_job(Users::Digests::Monthly::EmailSendingJob)
    end
  end
end
