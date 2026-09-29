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

    describe 'explore_features after Oban took the mail over' do
      before do
        job_owner!('command:users.explore_features_mail', :sidekiq)
        user
        job_owner!('command:users.explore_features_mail', :oban)
        JobOutbox.delete_all
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear
      end

      it 'forwards the queued job to the outbox under its own job id instead of mailing, once per job' do
        job = described_class.new(user.id, 'explore_features')

        expect { job.perform(user.id, 'explore_features') }.not_to have_enqueued_mail(UsersMailer, :explore_features)
        job.perform(user.id, 'explore_features')

        expect(JobOutbox.sole).to have_attributes(event_id: job.job_id, command_type: 'users.explore_features_mail',
                                                  aggregate_id: user.id,
                                                  payload: { 'user_id' => user.id, 'locale' => 'en' })
      end

      it 'forwards a serialized queued locale once even when the worker locale differs' do
        queued_job = I18n.with_locale(:fr) do
          described_class.perform_later(user.id, 'explore_features')
          ActiveJob::Base.queue_adapter.enqueued_jobs.last
        end

        I18n.with_locale(:de) { perform_enqueued_jobs(only: described_class) }

        expect(JobOutbox.sole).to have_attributes(event_id: queued_job['job_id'],
                                                  payload: { 'user_id' => user.id, 'locale' => 'fr' })

        I18n.with_locale(:en) { ActiveJob::Base.execute(queued_job) }

        expect(JobOutbox.count).to eq(1)
      end

      it 'still sends every other type through Sidekiq' do
        user
        JobOutbox.delete_all

        expect { described_class.perform_now(user.id, 'welcome') }.to have_enqueued_mail(UsersMailer, :welcome)
        expect(JobOutbox.count).to eq(0)
      end
    end

    describe 'wave-2 user mails' do
      let(:token) { Auth::IssueAccountLinkToken.new(user, provider: 'google_oauth2', uid: 'uid-1').call }
      let(:link_url) { "https://example.test/auth/account_link?token=#{token}" }
      let(:wave2_mails) do
        {
          'welcome' => {},
          'archival_approaching' => { epoch: '2026-03-29T01:30:00+02:00' },
          'oauth_account_link' => { provider_label: 'Google', link_url: },
          'account_destroy_confirmation' => { link_url: }
        }
      end

      before do
        allow(UsersMailer).to receive(:with).and_call_original
        user
        JobOutbox.delete_all
        clear_enqueued_jobs
      end

      it 'each wave-2 type owned by oban forwards with event_id = job_id and enqueues no delivery' do
        wave2_mails.each do |email_type, options|
          job_owner!("command:#{UserMailCommands::TYPES.fetch(email_type)}", :oban)
          job = described_class.new(user.id, email_type, **options)

          expect { job.perform_now }.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
          expect(JobOutbox.find(job.job_id)).to have_attributes(command_type: UserMailCommands::TYPES.fetch(email_type),
                                                                aggregate_id: user.id)
        end
      end

      it "each wave-2 type owned by sidekiq enqueues today's delivery" do
        wave2_mails.each do |email_type, options|
          job_owner!("command:#{UserMailCommands::TYPES.fetch(email_type)}", :sidekiq)

          expect { described_class.perform_now(user.id, email_type, **options) }
            .to have_enqueued_mail(UsersMailer, email_type.to_sym).with(params: { user:, **options }, args: [])
        end
        expect(JobOutbox.count).to eq(0)
      end

      it 'an old archival job without epoch forwards the user\'s 11_5mo mark as epoch' do
        warnings = { 'archival_warnings' => { '11_5mo' => '2026-09-01T03:00:00+02:00' } }
        user.update_columns(settings: user.settings.merge(warnings))
        job_owner!('command:mail.user.archival_approaching', :oban)
        job = described_class.new(user.id, 'archival_approaching')

        job.perform_now

        expect(JobOutbox.find(job.job_id).payload).to eq(
          'user_id' => user.id, 'locale' => 'en', 'epoch' => '2026-09-01T03:00:00+02:00'
        )
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

    context 'when email_type is a legacy trial lifecycle email' do
      %w[trial_expired trial_expires_soon post_trial_reminder_early post_trial_reminder_late].each do |email_type|
        it "skips #{email_type}" do
          expect do
            described_class.perform_now(user.id, email_type)
          end.not_to have_enqueued_job(ActionMailer::MailDeliveryJob)
        end

        it "logs that #{email_type} was skipped" do
          allow(Rails.logger).to receive(:info)

          described_class.perform_now(user.id, email_type)

          expect(Rails.logger).to have_received(:info).with(/skipping legacy Manager-owned email_type=#{email_type}/)
        end

        it "delivers nothing for #{email_type} when a stale ActionMailer job bypasses this wrapper" do
          expect do
            UsersMailer.with(user: user).public_send(email_type).deliver_now
          end.not_to(change { ActionMailer::Base.deliveries.size })
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
