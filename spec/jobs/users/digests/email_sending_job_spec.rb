# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::Digests::EmailSendingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }
    let(:year) { 2024 }
    let!(:digest) { create(:users_digest, user: user, year: year, period_type: :yearly) }

    subject { described_class.perform_now(user.id, year) }

    let(:mail_message) { double('MailMessage', deliver_later: true) }
    let(:mailer_with_params) { double('MailerWithParams', year_end_digest: mail_message) }

    before do
      allow(Users::DigestsMailer).to receive(:with).and_return(mailer_with_params)
    end

    it 'enqueues to the mailers queue' do
      expect(described_class.new.queue_name).to eq('mailers')
    end

    context 'when user has digest emails enabled' do
      it 'sends the email' do
        subject

        expect(Users::DigestsMailer).to have_received(:with).with(user: user, digest: digest)
      end

      it 'updates the sent_at timestamp' do
        expect { subject }.to change { digest.reload.sent_at }.from(nil)
      end
    end

    context 'when user has digest emails disabled' do
      before do
        user.update!(settings: user.settings.merge('digest_emails_enabled' => false))
      end

      it 'does not send the email' do
        subject

        expect(Users::DigestsMailer).not_to have_received(:with)
      end
    end

    context 'when digest does not exist' do
      before { digest.destroy }

      it 'does not send the email' do
        subject

        expect(Users::DigestsMailer).not_to have_received(:with)
      end
    end

    context 'when digest was already sent' do
      before { digest.update!(sent_at: 1.day.ago) }

      it 'does not send the email again' do
        subject

        expect(Users::DigestsMailer).not_to have_received(:with)
      end
    end

    context 'when user does not exist' do
      before { user.destroy }

      it 'does not raise error' do
        expect { described_class.perform_now(999_999, year) }.not_to raise_error
      end

      it 'reports the exception' do
        expect(ExceptionReporter).to receive(:call).with(
          'Users::Digests::EmailSendingJob',
          anything
        )

        described_class.perform_now(999_999, year)
      end
    end
  end
end
