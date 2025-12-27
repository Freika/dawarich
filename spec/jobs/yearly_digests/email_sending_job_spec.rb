# frozen_string_literal: true

require 'rails_helper'

RSpec.describe YearlyDigests::EmailSendingJob, type: :job do
  describe '#perform' do
    let!(:user) { create(:user) }
    let(:year) { 2024 }
    let!(:digest) { create(:yearly_digest, user: user, year: year, period_type: :yearly) }

    subject { described_class.perform_now(user.id, year) }

    before do
      # Mock the mailer
      allow(YearlyDigestsMailer).to receive_message_chain(:with, :year_end_digest, :deliver_later)
    end

    it 'enqueues to the mailers queue' do
      expect(described_class.new.queue_name).to eq('mailers')
    end

    context 'when user has digest emails enabled' do
      it 'sends the email' do
        subject

        expect(YearlyDigestsMailer).to have_received(:with).with(user: user, digest: digest)
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

        expect(YearlyDigestsMailer).not_to have_received(:with)
      end
    end

    context 'when digest does not exist' do
      before { digest.destroy }

      it 'does not send the email' do
        subject

        expect(YearlyDigestsMailer).not_to have_received(:with)
      end
    end

    context 'when digest was already sent' do
      before { digest.update!(sent_at: 1.day.ago) }

      it 'does not send the email again' do
        subject

        expect(YearlyDigestsMailer).not_to have_received(:with)
      end
    end

    context 'when user does not exist' do
      before { user.destroy }

      it 'does not raise error' do
        expect { described_class.perform_now(999_999, year) }.not_to raise_error
      end

      it 'reports the exception' do
        expect(ExceptionReporter).to receive(:call).with(
          'YearlyDigests::EmailSendingJob',
          anything
        )

        described_class.perform_now(999_999, year)
      end
    end
  end
end
