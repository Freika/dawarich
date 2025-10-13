# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::InvitationPolicy, type: :policy do
  let(:family) { create(:family) }
  let(:owner) { family.creator }
  let(:member) { create(:user) }
  let(:other_user) { create(:user) }
  let(:invitation) { create(:family_invitation, family: family, invited_by: owner) }

  before do
    create(:family_membership, family: family, user: owner, role: :owner)
    create(:family_membership, family: family, user: member, role: :member)
  end

  describe '#create?' do
    context 'when user is family owner' do
      before do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
      end

      it 'allows family owner to create invitations' do
        policy = described_class.new(owner, invitation)

        expect(policy).to permit(:create)
      end
    end

    context 'when user is regular family member' do
      before do
        allow(member).to receive(:family).and_return(family)
        allow(member).to receive(:family_owner?).and_return(false)
      end

      it 'denies regular family member from creating invitations' do
        policy = described_class.new(member, invitation)

        expect(policy).not_to permit(:create)
      end
    end

    context 'when user is not in the family' do
      it 'denies user not in the family from creating invitations' do
        policy = described_class.new(other_user, invitation)

        expect(policy).not_to permit(:create)
      end
    end

    context 'with unauthenticated user' do
      it 'denies unauthenticated user from creating invitations' do
        policy = described_class.new(nil, invitation)

        expect(policy).not_to permit(:create)
      end
    end
  end

  describe '#accept?' do
    context 'when user email matches invitation email' do
      let(:invited_user) { create(:user, email: invitation.email) }

      it 'allows user to accept invitation sent to their email' do
        policy = described_class.new(invited_user, invitation)

        expect(policy).to permit(:accept)
      end
    end

    context 'when user email does not match invitation email' do
      it 'denies user with different email from accepting invitation' do
        policy = described_class.new(other_user, invitation)

        expect(policy).not_to permit(:accept)
      end
    end

    context 'when family owner tries to accept invitation' do
      it 'denies family owner from accepting invitation sent to different email' do
        policy = described_class.new(owner, invitation)

        expect(policy).not_to permit(:accept)
      end
    end

    context 'with unauthenticated user' do
      it 'denies unauthenticated user from accepting invitation' do
        policy = described_class.new(nil, invitation)

        expect(policy).not_to permit(:accept)
      end
    end
  end

  describe '#destroy?' do
    context 'when user is family owner' do
      before do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
      end

      it 'allows family owner to cancel invitations' do
        policy = described_class.new(owner, invitation)

        expect(policy).to permit(:destroy)
      end
    end

    context 'when user is regular family member' do
      before do
        allow(member).to receive(:family).and_return(family)
        allow(member).to receive(:family_owner?).and_return(false)
      end

      it 'denies regular family member from cancelling invitations' do
        policy = described_class.new(member, invitation)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'when user is not in the family' do
      it 'denies user not in the family from cancelling invitations' do
        policy = described_class.new(other_user, invitation)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'with unauthenticated user' do
      it 'denies unauthenticated user from cancelling invitations' do
        policy = described_class.new(nil, invitation)

        expect(policy).not_to permit(:destroy)
      end
    end
  end

  describe 'edge cases' do
    context 'when invitation belongs to different family' do
      let(:other_family) { create(:family) }
      let(:other_family_owner) { other_family.creator }
      let(:other_invitation) { create(:family_invitation, family: other_family, invited_by: other_family_owner) }

      before do
        create(:family_membership, family: other_family, user: other_family_owner, role: :owner)
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
      end

      it 'denies owner from creating invitations for different family' do
        policy = described_class.new(owner, other_invitation)

        expect(policy).not_to permit(:create)
      end

      it 'denies owner from destroying invitations for different family' do
        policy = described_class.new(owner, other_invitation)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'with expired invitation' do
      let(:expired_invitation) { create(:family_invitation, :expired, family: family, invited_by: owner) }
      let(:invited_user) { create(:user, email: expired_invitation.email) }

      it 'still allows user to attempt to accept expired invitation (business logic handles expiry)' do
        policy = described_class.new(invited_user, expired_invitation)

        expect(policy).to permit(:accept)
      end

      it 'allows owner to destroy expired invitation' do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
        policy = described_class.new(owner, expired_invitation)

        expect(policy).to permit(:destroy)
      end
    end

    context 'with accepted invitation' do
      let(:accepted_invitation) { create(:family_invitation, :accepted, family: family, invited_by: owner) }

      it 'allows owner to destroy accepted invitation' do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
        policy = described_class.new(owner, accepted_invitation)

        expect(policy).to permit(:destroy)
      end
    end

    context 'with cancelled invitation' do
      let(:cancelled_invitation) { create(:family_invitation, :cancelled, family: family, invited_by: owner) }

      it 'allows owner to destroy cancelled invitation' do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
        policy = described_class.new(owner, cancelled_invitation)

        expect(policy).to permit(:destroy)
      end
    end
  end

  describe 'authorization consistency' do
    it 'ensures owner can both create and destroy invitations' do
      allow(owner).to receive(:family).and_return(family)
      allow(owner).to receive(:family_owner?).and_return(true)
      policy = described_class.new(owner, invitation)

      expect(policy).to permit(:create)
      expect(policy).to permit(:destroy)
    end

    it 'ensures regular members cannot create or destroy invitations' do
      allow(member).to receive(:family).and_return(family)
      allow(member).to receive(:family_owner?).and_return(false)
      policy = described_class.new(member, invitation)

      expect(policy).not_to permit(:create)
      expect(policy).not_to permit(:destroy)
    end

    it 'ensures invited users can only accept their own invitations' do
      invited_user = create(:user, email: invitation.email)
      policy = described_class.new(invited_user, invitation)

      expect(policy).to permit(:accept)
      expect(policy).not_to permit(:create)
      expect(policy).not_to permit(:destroy)
    end
  end
end
