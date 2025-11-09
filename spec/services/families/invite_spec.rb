# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::Invite do
  let(:owner) { create(:user) }
  let(:family) { create(:family, creator: owner) }
  let!(:owner_membership) { create(:family_membership, user: owner, family: family, role: :owner) }
  let(:email) { 'invitee@example.com' }
  let(:service) { described_class.new(family: family, email: email, invited_by: owner) }

  describe '#call' do
    context 'when invitation is valid' do
      it 'creates an invitation' do
        expect { service.call }.to change(Family::Invitation, :count).by(1)

        invitation = owner.sent_family_invitations.last

        expect(invitation.family).to eq(family)
        expect(invitation.email).to eq(email)
        expect(invitation.invited_by).to eq(owner)
      end

      it 'enqueues invitation sending job' do
        expect(Family::Invitations::SendingJob).to receive(:perform_later).with(an_instance_of(Integer))
        service.call
      end

      it 'sends invitation email' do
        expect(Family::Invitations::SendingJob).to receive(:perform_later).and_call_original
        service.call
      end

      it 'sends notification to inviter' do
        expect { service.call }.to change(Notification, :count).by(1)

        notification = owner.notifications.last

        expect(notification.user).to eq(owner)
        expect(notification.title).to eq('Invitation Sent')
      end

      it 'returns true' do
        expect(service.call).to be true
      end
    end

    context 'when inviter is not family owner' do
      let(:member) { create(:user) }
      let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }
      let(:service) { described_class.new(family: family, email: email, invited_by: member) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create invitation' do
        expect { service.call }.not_to change(Family::Invitation, :count)
      end
    end

    context 'when family is at max capacity' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        # Create max members (5 total including owner)
        create_list(:family_membership, Family::MAX_MEMBERS - 1, family: family, role: :member)
      end

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create invitation' do
        expect { service.call }.not_to change(Family::Invitation, :count)
      end
    end

    context 'when user is already in a family' do
      let(:existing_user) { create(:user, email: email) }
      let(:other_family) { create(:family) }

      before do
        create(:family_membership, user: existing_user, family: other_family)
      end

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create invitation' do
        expect { service.call }.not_to change(Family::Invitation, :count)
      end
    end

    context 'when pending invitation already exists' do
      before do
        create(:family_invitation, family: family, email: email, invited_by: owner)
      end

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create another invitation' do
        expect { service.call }.not_to change(Family::Invitation, :count)
      end
    end

    context 'with invalid email' do
      let(:service) { described_class.new(family: family, email: 'invalid-email', invited_by: owner) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'has validation errors' do
        service.call
        expect(service.errors[:email]).to be_present
      end
    end
  end

  describe 'email normalization' do
    let(:service) { described_class.new(family: family, email: ' UPPER@EXAMPLE.COM ', invited_by: owner) }

    it 'normalizes email to lowercase and strips whitespace' do
      service.call
      invitation = family.family_invitations.last

      expect(invitation.email).to eq('upper@example.com')
    end
  end

  describe 'validations' do
    it 'validates presence of email' do
      service = described_class.new(family: family, email: '', invited_by: owner)
      expect(service).not_to be_valid
      expect(service.errors[:email]).to include("can't be blank")
    end

    it 'validates email format' do
      service = described_class.new(family: family, email: 'invalid-email', invited_by: owner)
      expect(service).not_to be_valid
      expect(service.errors[:email]).to include('is invalid')
    end
  end
end
