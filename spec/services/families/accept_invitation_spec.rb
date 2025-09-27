# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Families::AcceptInvitation do
  let(:family) { create(:family) }
  let(:invitee) { create(:user, email: 'invitee@example.com') }
  let(:invitation) { create(:family_invitation, family: family, email: invitee.email) }
  let(:service) { described_class.new(invitation: invitation, user: invitee) }

  describe '#call' do
    context 'when invitation can be accepted' do
      it 'creates membership for user' do
        expect { service.call }.to change(FamilyMembership, :count).by(1)
        membership = invitee.family_membership
        expect(membership.family).to eq(family)
        expect(membership.role).to eq('member')
      end

      it 'updates invitation status to accepted' do
        service.call
        invitation.reload
        expect(invitation.status).to eq('accepted')
      end

      it 'sends notifications to both parties' do
        expect { service.call }.to change(Notification, :count).by(2)

        user_notification = Notification.find_by(user: invitee, title: 'Welcome to Family')
        expect(user_notification).to be_present

        owner_notification = Notification.find_by(user: family.creator, title: 'New Family Member')
        expect(owner_notification).to be_present
      end

      it 'returns true' do
        expect(service.call).to be true
      end
    end

    context 'when user is already in another family' do
      let(:other_family) { create(:family) }
      let!(:existing_membership) { create(:family_membership, user: invitee, family: other_family) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(FamilyMembership, :count)
      end

      it 'sets appropriate error message' do
        service.call
        expect(service.error_message).to eq('You must leave your current family before joining a new one.')
      end

      it 'does not change user family' do
        expect { service.call }.not_to(change { invitee.reload.family })
      end
    end

    context 'when invitation is expired' do
      let(:invitation) { create(:family_invitation, family: family, email: invitee.email, expires_at: 1.day.ago) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(FamilyMembership, :count)
      end
    end

    context 'when invitation is not pending' do
      let(:invitation) { create(:family_invitation, :accepted, family: family, email: invitee.email) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(FamilyMembership, :count)
      end
    end

    context 'when email does not match user' do
      let(:wrong_user) { create(:user, email: 'wrong@example.com') }
      let(:service) { described_class.new(invitation: invitation, user: wrong_user) }

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(FamilyMembership, :count)
      end
    end

    context 'when family is at max capacity' do
      before do
        # Fill family to max capacity
        create_list(:family_membership, Family::MAX_MEMBERS, family: family, role: :member)
      end

      it 'returns false' do
        expect(service.call).to be false
      end

      it 'does not create membership' do
        expect { service.call }.not_to change(FamilyMembership, :count)
      end
    end
  end
end
