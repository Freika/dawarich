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

    context 'integration test' do
      it 'actually sends the email' do
        expect do
          described_class.perform_now(invitation.id)
        end.to change { ActionMailer::Base.deliveries.count }.by(1)

        email = ActionMailer::Base.deliveries.last
        expect(email.to).to include(invitation.email)
        expect(email.subject).to include("You've been invited to join #{family.name}")
      end
    end
  end
end
