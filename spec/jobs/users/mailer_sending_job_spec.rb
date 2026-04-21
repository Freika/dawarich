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

    context 'when email_type is trial_expires_soon' do
      context 'with trial user' do
        it 'sends trial_expires_soon email' do
          expect(UsersMailer).to receive(:with).with({ user: user })
          expect(UsersMailer).to receive(:trial_expires_soon).and_return(mailer_double)
          expect(mailer_double).to receive(:deliver_later)

          described_class.perform_now(user.id, 'trial_expires_soon')
        end
      end

      context 'with active user' do
        let(:active_user) { create(:user).tap { |u| u.update!(status: :active) } }

        it 'skips sending trial_expires_soon email' do
          expect(UsersMailer).not_to receive(:with)
          expect(UsersMailer).not_to receive(:trial_expires_soon)

          described_class.perform_now(active_user.id, 'trial_expires_soon')
        end
      end
    end

    context 'when email_type is trial_expired' do
      context 'with trial user' do
        it 'sends trial_expired email' do
          expect(UsersMailer).to receive(:with).with({ user: user })
          expect(UsersMailer).to receive(:trial_expired).and_return(mailer_double)
          expect(mailer_double).to receive(:deliver_later)

          described_class.perform_now(user.id, 'trial_expired')
        end
      end

      context 'with active user' do
        let(:active_user) { create(:user).tap { |u| u.update!(status: :active) } }

        it 'skips sending trial_expired email' do
          expect(UsersMailer).not_to receive(:with)
          expect(UsersMailer).not_to receive(:trial_expired)

          described_class.perform_now(active_user.id, 'trial_expired')
        end
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

    context 'when legacy_trial_mail_cancelled? is true' do
      # Coordination point: user.rb agent is adding this predicate so users
      # who already cancelled the legacy trial don't get re-nagged by any
      # `trial_*` mailer. Stubbing both shapes (define and stub) for safety.
      let(:cancelled_user) do
        create(:user, :trial).tap do |u|
          u.define_singleton_method(:legacy_trial_mail_cancelled?) { true }
        end
      end

      it 'skips trial_* emails without raising' do
        allow(User).to receive(:find_by).with(id: cancelled_user.id).and_return(cancelled_user)

        expect(UsersMailer).not_to receive(:trial_expires_soon)
        described_class.perform_now(cancelled_user.id, 'trial_expires_soon')
      end

      it 'still sends non-trial emails (e.g. welcome)' do
        allow(User).to receive(:find_by).with(id: cancelled_user.id).and_return(cancelled_user)

        expect(UsersMailer).to receive(:with).with({ user: cancelled_user })
        expect(UsersMailer).to receive(:welcome).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(cancelled_user.id, 'welcome')
      end
    end
  end
end
