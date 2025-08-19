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
      it 'raises ActiveRecord::RecordNotFound' do
        user.destroy

        expect {
          described_class.perform_now(user.id, 'welcome')
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe '#trial_related_email?' do
    subject { described_class.new }

    it 'returns true for trial_expires_soon' do
      expect(subject.send(:trial_related_email?, 'trial_expires_soon')).to be true
    end

    it 'returns true for trial_expired' do
      expect(subject.send(:trial_related_email?, 'trial_expired')).to be true
    end

    it 'returns false for welcome' do
      expect(subject.send(:trial_related_email?, 'welcome')).to be false
    end

    it 'returns false for explore_features' do
      expect(subject.send(:trial_related_email?, 'explore_features')).to be false
    end

    it 'returns false for unknown email types' do
      expect(subject.send(:trial_related_email?, 'unknown_email')).to be false
    end
  end
end
