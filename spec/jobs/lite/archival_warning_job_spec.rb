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

    context 'when there are no Lite users' do
      before { lite_user.destroy }

      it 'does not create any notifications' do
        expect { described_class.perform_now }.not_to change(Notification, :count)
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
          .with(lite_user.id, 'archival_approaching')
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

      it 'creates an in-app banner notification about archived data' do
        expect { described_class.perform_now }.to change(Notification, :count)
        notification = Notification.where(user: lite_user).order(:created_at).last
        expect(notification.kind).to eq('warning')
        expect(notification.title).to include('archived')
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
  end
end
