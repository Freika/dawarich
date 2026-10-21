# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Lite::ArchivalWarningJob, type: :job do
  describe '#perform' do
    # Create users then set plan via update_column to avoid the
    # after_commit :activate callback overriding plan to :self_hoster.
    let!(:lite_user) { create(:user).tap { |u| u.update_column(:plan, User.plans[:lite]) } }
    let!(:pro_user) { create(:user).tap { |u| u.update_column(:plan, User.plans[:pro]) } }
    let!(:self_hoster) { create(:user) }

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
    end

    describe 'ownership gate and mark-then-effect order' do
      let(:second_lite_user) { create(:user).tap { |u| u.update_column(:plan, User.plans[:lite]) } }

      def archival_warnings(user)
        user.reload.settings&.dig('archival_warnings')
      end

      it 'takes the ownership gate once per user' do
        second_lite_user
        expect(JobOwnership).to receive(:with_owner).with(described_class::OWNERSHIP_KEY).twice.and_call_original

        described_class.perform_now
      end

      it 'cron key owned by oban: nothing is marked, notified or produced' do
        create(:point, user: lite_user, timestamp: (11.months + 15.days).ago.to_i)
        create(:point, user: second_lite_user, timestamp: 12.months.ago.to_i)
        job_owner!(described_class::OWNERSHIP_KEY, :oban)
        job_owner!('command:mail.user.archival_approaching', :oban)
        JobOutbox.delete_all
        clear_enqueued_jobs
        expect(JobOwnership).to receive(:with_owner).once.and_call_original

        expect { described_class.perform_now }.not_to change(Notification, :count)
        expect(Users::MailerSendingJob).not_to have_been_enqueued
        expect(JobOutbox.count).to eq(0)
        expect([archival_warnings(lite_user), archival_warnings(second_lite_user)]).to eq([nil, nil])
      end

      it 'a failing effect rolls back the marks' do
        create(:point, user: lite_user, timestamp: 11.months.ago.to_i)
        marks_seen_by_effect = nil
        allow(Notification).to receive(:create!) do
          marks_seen_by_effect = archival_warnings(lite_user)
          raise ActiveRecord::StatementInvalid, 'notification insert failed'
        end

        expect { described_class.perform_now }.to raise_error(ActiveRecord::StatementInvalid)
        expect(marks_seen_by_effect).to include('11mo')
        expect(archival_warnings(lite_user)).to be_nil
      end

      it 'sidekiq arm: an enqueue error rolls the marks back, so the next run sends the mail' do
        create(:point, user: lite_user, timestamp: (11.months + 15.days).ago.to_i)
        adapter = Users::MailerSendingJob.queue_adapter
        allow(adapter).to receive(:enqueue_at).and_raise(RedisClient::CannotConnectError, 'redis down')

        expect { described_class.perform_now }.to raise_error(RedisClient::CannotConnectError)
        expect(archival_warnings(lite_user)).to be_nil

        allow(adapter).to receive(:enqueue_at).and_call_original
        expect { described_class.perform_now }.to have_enqueued_job(Users::MailerSendingJob)
          .with(lite_user.id, 'archival_approaching', epoch: an_instance_of(String))
        expect(archival_warnings(lite_user)).to include('11_5mo')
      end

      it 'skips a user whose threshold another runtime marked after the batch was loaded' do
        create(:point, user: lite_user, timestamp: (11.months + 15.days).ago.to_i)
        phoenix_marks = { '11mo' => '2026-01-01T00:00:00Z', '11_5mo' => '2026-01-01T00:00:00Z' }
        allow(JobOwnership).to receive(:with_owner).and_wrap_original do |original, *args, &block|
          User.where(id: lite_user.id).update_all(settings: { 'archival_warnings' => phoenix_marks })
          original.call(*args, &block)
        end

        expect { described_class.perform_now }.not_to have_enqueued_job(Users::MailerSendingJob)
        expect(archival_warnings(lite_user)).to eq(phoenix_marks)
      end

      it 'still acts on a threshold whose marker is blank' do
        create(:point, user: lite_user, timestamp: (11.months + 15.days).ago.to_i)
        lite_user.update_column(:settings, { 'archival_warnings' => { '11mo' => 'x', '11_5mo' => '' } })

        expect { described_class.perform_now }.to have_enqueued_job(Users::MailerSendingJob)
        expect(archival_warnings(lite_user)['11_5mo']).to be_present
      end

      it 'rejects split cron and mail ownership, then sends with source ownership' do
        create(:point, user: lite_user, timestamp: (11.months + 15.days).ago.to_i)
        job_owner!('command:mail.user.archival_approaching', :oban)
        JobOutbox.delete_all
        clear_enqueued_jobs

        expect { described_class.perform_now }.to raise_error(JobOwnership::InconsistentOwners)
        expect(archival_warnings(lite_user)).to be_nil
        expect(JobOutbox.count).to eq(0)
        expect(Users::MailerSendingJob).not_to have_been_enqueued

        JobOwnership.put!(described_class::OWNERSHIP_KEY, :sidekiq, pinned: false, by: 'spec')
        described_class.perform_now

        expect(Users::MailerSendingJob).to have_been_enqueued
          .with(lite_user.id, 'archival_approaching', epoch: archival_warnings(lite_user)['11_5mo'])
        expect(JobOutbox.count).to eq(0)
      end
    end

    context 'when running on a self-hosted instance' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
        create(:point, user: lite_user, timestamp: 12.months.ago.to_i)
      end

      it 'is a no-op and does not create any notifications' do
        expect { described_class.perform_now }.not_to change(Notification, :count)
      end
    end

    context 'when there are no Lite users' do
      before { lite_user.destroy }

      it 'does not create any notifications' do
        expect { described_class.perform_now }.not_to change(Notification, :count)
      end
    end

    context 'when a Lite user is a member of a family-plan family' do
      let!(:family_owner) { create(:user).tap { |u| u.update_column(:plan, User.plans[:family]) } }
      let!(:family) { create(:family, creator: family_owner) }

      before do
        create(:family_membership, :owner, family: family, user: family_owner)
        create(:family_membership, family: family, user: lite_user)
        create(:point, user: lite_user, timestamp: 12.months.ago.to_i)
      end

      it 'does not create an archival warning for the family member' do
        expect { described_class.perform_now }
          .not_to(change { Notification.where(user: lite_user).count })
      end
    end

    context 'when a Lite user has data approaching 11 months old' do
      before do
        create(:point, user: lite_user, timestamp: 11.months.ago.to_i)
      end

      it 'creates an in-app warning notification' do
        expect { described_class.perform_now }.to change(Notification, :count).by(1)
        notification = Notification.last
        expect(notification.user).to eq(lite_user)
        expect(notification.kind).to eq('warning')
        expect(notification.title).to include('archive')
      end

      it 'uses the recipient saved locale for the persisted notification' do
        lite_user.update!(settings: { 'locale' => 'fr' })

        I18n.with_locale(:en) { described_class.perform_now }

        notification = Notification.find_by!(user: lite_user)
        expect(notification.title).to eq('Vos données les plus anciennes seront archivées dans 30 jours')
        expect(notification.content).to include('Votre plus ancien mois de données de localisation')
      end

      it 'does not warn the same user twice for the 11-month threshold' do
        described_class.perform_now
        expect { described_class.perform_now }.not_to change(Notification, :count)
      end
    end

    context 'when a Lite user has data approaching 11.5 months old' do
      before do
        create(:point, user: lite_user, timestamp: (11.months + 15.days).ago.to_i)
      end

      it 'enqueues an archival warning email' do
        expect { described_class.perform_now }
          .to have_enqueued_job(Users::MailerSendingJob)
          .with(lite_user.id, 'archival_approaching', epoch: an_instance_of(String))
      end

      it 'does not send the email twice for the same threshold' do
        described_class.perform_now
        # Clear the queue between runs to isolate the second invocation
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
        expect { described_class.perform_now }
          .not_to have_enqueued_job(Users::MailerSendingJob)
      end
    end

    context 'when a Lite user has data reaching 12 months old' do
      before do
        create(:point, user: lite_user, timestamp: 12.months.ago.to_i)
      end

      it 'creates only the most severe notification (archived), not all three' do
        expect { described_class.perform_now }.to change(Notification, :count).by(1)
        notification = Notification.where(user: lite_user).order(:created_at).last
        expect(notification.kind).to eq('warning')
        expect(notification.title).to include('archived')
      end

      it 'does not enqueue the 11.5-month email when all thresholds crossed at once' do
        expect { described_class.perform_now }
          .not_to have_enqueued_job(Users::MailerSendingJob)
      end

      it 'marks all thresholds as sent so none fire on subsequent runs' do
        described_class.perform_now
        lite_user.reload
        warnings = lite_user.settings['archival_warnings']
        expect(warnings.keys).to contain_exactly('11mo', '11_5mo', '12mo')
      end
    end

    context 'when user is Pro or self-hoster' do
      before do
        create(:point, user: pro_user, timestamp: 13.months.ago.to_i)
        create(:point, user: self_hoster, timestamp: 13.months.ago.to_i)
      end

      it 'does not create notifications for non-Lite users' do
        expect { described_class.perform_now }.not_to change(Notification, :count)
      end

      it 'does not enqueue emails for non-Lite users' do
        expect { described_class.perform_now }
          .not_to have_enqueued_job(Users::MailerSendingJob)
      end
    end

    context 'when Lite user has no old data' do
      before do
        create(:point, user: lite_user, timestamp: 1.month.ago.to_i)
      end

      it 'does not create any notifications' do
        expect { described_class.perform_now }.not_to change(Notification, :count)
      end
    end

    context 'when Lite user upgrades to Pro' do
      before do
        create(:point, user: lite_user, timestamp: 12.months.ago.to_i)
        lite_user.update!(plan: :pro)
      end

      it 'does not warn Pro users even if they have old data' do
        expect { described_class.perform_now }.not_to change(Notification, :count)
      end
    end

    context 'when a Pro user with years of history is freshly downgraded to Lite' do
      let!(:downgraded) { create(:user).tap { |u| u.update_column(:plan, User.plans[:pro]) } }

      before do
        create(:point, user: downgraded, timestamp: 14.months.ago.to_i)
        downgraded.update!(plan: :lite)
      end

      it 'sends the archived notification on the first run' do
        expect { described_class.perform_now }
          .to change { Notification.where(user: downgraded).count }.by(1)

        notification = Notification.where(user: downgraded).order(:created_at).last
        expect(notification.title).to include('archived')
      end

      it 'does not enqueue the email when all thresholds are crossed at once' do
        expect { described_class.perform_now }
          .not_to have_enqueued_job(Users::MailerSendingJob)
      end

      it 'notifies again when the user upgrades and is downgraded again' do
        described_class.perform_now
        downgraded.update!(plan: :pro)
        downgraded.update!(plan: :lite)

        expect { described_class.perform_now }
          .to change { Notification.where(user: downgraded).count }.by(1)
      end
    end
  end
end
