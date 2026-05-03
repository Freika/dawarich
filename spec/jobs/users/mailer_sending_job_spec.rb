# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::MailerSendingJob, type: :job do
  let(:user) { create(:user, :trial) }
  let(:mailer_double) { double('mailer', deliver_later: true) }

  before do
    allow(UsersMailer).to receive(:with).and_return(UsersMailer)
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  describe '#perform' do
    context 'when email_type is welcome' do
      it 'sends welcome email to trial user' do
        expect(UsersMailer).to receive(:with).with({ user: user })
        expect(UsersMailer).to receive(:welcome).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(user.id, 'welcome')
      end

      it 'sends welcome email to active user' do
        active_user = create(:user)
        expect(UsersMailer).to receive(:with).with({ user: active_user })
        expect(UsersMailer).to receive(:welcome).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(active_user.id, 'welcome')
      end
    end

    context 'when email_type is explore_features' do
      it 'sends explore_features email to trial user' do
        expect(UsersMailer).to receive(:with).with({ user: user })
        expect(UsersMailer).to receive(:explore_features).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(user.id, 'explore_features')
      end

      it 'sends explore_features email to active user' do
        active_user = create(:user)
        expect(UsersMailer).to receive(:with).with({ user: active_user })
        expect(UsersMailer).to receive(:explore_features).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(active_user.id, 'explore_features')
      end
    end

    context 'with additional options' do
      it 'merges options with user params' do
        custom_options = { custom_data: 'test', priority: :high }
        expected_params = { user: user, custom_data: 'test', priority: :high }

        expect(UsersMailer).to receive(:with).with(expected_params)
        expect(UsersMailer).to receive(:welcome).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(user.id, 'welcome', **custom_options)
      end
    end

    context 'when user is deleted' do
      it 'does not raise an error' do
        user.destroy

        expect do
          described_class.perform_now(user.id, 'welcome')
        end.not_to raise_error
      end
    end

    context 'when email_type is unknown' do
      it 'raises UnknownEmailType so Sidekiq can retry / Sentry can alert' do
        expect do
          described_class.perform_now(user.id, 'totally_made_up_type')
        end.to raise_error(Users::MailerSendingJob::UnknownEmailType, /totally_made_up_type/)
      end
    end

    context 'when email_type is a billing email never implemented in Dawarich' do
      # These types are owned exclusively by Manager's BillingMailer. If a stale
      # job ever appears with these types it must surface loudly via
      # UnknownEmailType so Sentry alerts and Sidekiq can be drained manually.
      %w[trial_first_payment_soon trial_converted
         pending_payment_day_1 pending_payment_day_3 pending_payment_day_7].each do |billing_type|
        it "raises UnknownEmailType for #{billing_type}" do
          expect do
            described_class.perform_now(user.id, billing_type)
          end.to raise_error(Users::MailerSendingJob::UnknownEmailType, /#{billing_type}/)
        end
      end
    end

    context 'when email_type is a transitional trial-reminder' do
      # The four trial-reminder types below were enqueued by Dawarich pre-billing
      # extraction. They're kept in MAILER_REGISTRY through the queue-drain
      # window so stale Sidekiq jobs fire normally instead of crashing.
      # Earliest removal: 2026-05-17 (deploy + 21 days). When you delete them,
      # also delete the registry entries, the mailer methods, and the templates.
      let(:active_user) { create(:user, skip_auto_trial: true, status: :active, active_until: 1.year.from_now) }
      let(:auto_converting_user) do
        create(:user, :trial, skip_auto_trial: true, active_until: 1.week.from_now, subscription_source: :paddle)
      end

      %w[trial_expires_soon trial_expired].each do |type|
        it "skips #{type} when the user is already active (no stale 'trial expires soon' to a paying user)" do
          expect(UsersMailer).not_to receive(:with)
          described_class.perform_now(active_user.id, type)
        end

        it "skips #{type} for an auto-converting trial (card on file — Paddle owns the lifecycle)" do
          expect(UsersMailer).not_to receive(:with)
          described_class.perform_now(auto_converting_user.id, type)
        end

        it "still delivers #{type} to a legacy trial user (drain path)" do
          expect(UsersMailer).to receive(:with).with({ user: user })
          expect(UsersMailer).to receive(type).and_return(mailer_double)
          expect(mailer_double).to receive(:deliver_later)
          described_class.perform_now(user.id, type)
        end
      end

      %w[post_trial_reminder_early post_trial_reminder_late].each do |type|
        it "skips #{type} when the user has converted to active" do
          expect(UsersMailer).not_to receive(:with)
          described_class.perform_now(active_user.id, type)
        end

        it "skips #{type} for an auto-converting trial (card on file)" do
          expect(UsersMailer).not_to receive(:with)
          described_class.perform_now(auto_converting_user.id, type)
        end

        it "still delivers #{type} to a legacy trial user (drain path)" do
          expect(UsersMailer).to receive(:with).with({ user: user })
          expect(UsersMailer).to receive(type).and_return(mailer_double)
          expect(mailer_double).to receive(:deliver_later)
          described_class.perform_now(user.id, type)
        end
      end
    end

    context 'registry coverage' do
      # Prove every entry in MAILER_REGISTRY actually resolves to a real mailer
      # action. A typo in the registry would otherwise silently break production.
      Users::MailerSendingJob::MAILER_REGISTRY.each do |email_type, (mailer_class_name, action)|
        it "routes #{email_type.inspect} to #{mailer_class_name}##{action}" do
          klass = mailer_class_name.constantize
          expect(klass.action_methods).to include(action.to_s)
        end
      end
    end
  end
end
