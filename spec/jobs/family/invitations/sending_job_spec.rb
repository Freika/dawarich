# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::Invitations::SendingJob, type: :job do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let(:invitation) { create(:family_invitation, family: family, invited_by: user, status: :pending) }

  describe '#perform' do
    context 'when invitation exists and is pending' do
      it 'sends the invitation email' do
        mailer_double = double('mailer')
        expect(FamilyMailer).to receive(:invitation).with(invitation).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_now)

        described_class.perform_now(invitation.id)
      end
    end

    context 'when invitation does not exist' do
      it 'does not raise an error' do
        expect do
          described_class.perform_now(999_999)
        end.not_to raise_error
      end

      it 'does not send any email' do
        expect(FamilyMailer).not_to receive(:invitation)

        described_class.perform_now(999_999)
      end
    end

    context 'when invitation is not pending' do
      let(:accepted_invitation) do
        create(:family_invitation, family: family, invited_by: user, status: :accepted)
      end

      it 'does not send the invitation email' do
        expect(FamilyMailer).not_to receive(:invitation)

        described_class.perform_now(accepted_invitation.id)
      end
    end

    context 'when invitation is cancelled' do
      let(:cancelled_invitation) do
        create(:family_invitation, family: family, invited_by: user, status: :cancelled)
      end

      it 'does not send the invitation email' do
        expect(FamilyMailer).not_to receive(:invitation)

        described_class.perform_now(cancelled_invitation.id)
      end
    end

    describe 'ownership of command:mail.family_invitation' do
      before do
        invitation
        JobOutbox.delete_all
        ActionMailer::Base.deliveries.clear
      end

      it 'owned by oban forwards and sends nothing' do
        job_owner!('command:mail.family_invitation', :oban)
        job = described_class.new(invitation.id)

        expect { job.perform_now }.not_to(change { ActionMailer::Base.deliveries.size })
        expect(JobOutbox.find(job.job_id)).to have_attributes(
          command_type: 'mail.family_invitation', aggregate_id: invitation.id,
          dedupe_key: "family-invitation:#{invitation.id}",
          payload: { 'invitation_id' => invitation.id, 'locale' => 'en' }
        )
      end

      it 'owned by sidekiq sends only while pending' do
        job_owner!('command:mail.family_invitation', :sidekiq)
        allow(FamilyMailer).to receive(:default).and_return(FamilyMailer.default.merge(from: 'noreply@example.test'))
        accepted = create(:family_invitation, family: family, invited_by: user, status: :accepted)

        expect { described_class.perform_now(accepted.id) }.not_to(change { ActionMailer::Base.deliveries.size })
        expect { described_class.perform_now(invitation.id) }.to change { ActionMailer::Base.deliveries.size }.by(1)
        expect(ActionMailer::Base.deliveries.last.to).to eq([invitation.email])
        expect(JobOutbox.count).to eq(0)
      end
    end

    context 'integration test' do
      before do
        ActionMailer::Base.deliveries.clear
        # Set a from address for the mailer to avoid SMTP errors
        allow(ActionMailer::Base).to receive(:default).and_return(from: 'noreply@dawarich.app')
      end

      it 'actually calls the mailer' do
        mailer = instance_double(ActionMailer::MessageDelivery)
        allow(FamilyMailer).to receive(:invitation).and_return(mailer)
        allow(mailer).to receive(:deliver_now)

        described_class.perform_now(invitation.id)

        expect(FamilyMailer).to have_received(:invitation).with(invitation)
        expect(mailer).to have_received(:deliver_now)
      end
    end
  end
end
