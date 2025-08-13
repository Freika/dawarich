require 'rails_helper'

RSpec.describe Users::MailerSendingJob, type: :job do
  let(:user) { create(:user, :trial) }
  let(:mailer_double) { double('mailer', deliver_later: true) }

  before do
    allow(UsersMailer).to receive(:with).and_return(UsersMailer)
  end

  describe '#perform' do
    context 'when email_type is welcome' do
      it 'sends welcome email' do
        expect(UsersMailer).to receive(:with).with({ user: user })
        expect(UsersMailer).to receive(:welcome).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(user.id, 'welcome')
      end
    end

    context 'when email_type is explore_features' do
      it 'sends explore_features email' do
        expect(UsersMailer).to receive(:with).with({ user: user })
        expect(UsersMailer).to receive(:explore_features).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(user.id, 'explore_features')
      end
    end

    context 'when email_type is trial_expires_soon' do
      it 'sends trial_expires_soon email' do
        expect(UsersMailer).to receive(:with).with({ user: user })
        expect(UsersMailer).to receive(:trial_expires_soon).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(user.id, 'trial_expires_soon')
      end
    end

    context 'when email_type is trial_expired' do
      it 'sends trial_expired email' do
        expect(UsersMailer).to receive(:with).with({ user: user })
        expect(UsersMailer).to receive(:trial_expired).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        described_class.perform_now(user.id, 'trial_expired')
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
end
