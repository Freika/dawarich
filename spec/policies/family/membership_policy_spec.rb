# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Family::MembershipPolicy, type: :policy do
  let(:family) { create(:family) }
  let(:owner) { family.creator }
  let(:member) { create(:user) }
  let(:another_member) { create(:user) }
  let(:other_user) { create(:user) }

  let(:owner_membership) { create(:family_membership, :owner, family: family, user: owner) }
  let(:member_membership) { create(:family_membership, family: family, user: member) }
  let(:another_member_membership) { create(:family_membership, family: family, user: another_member) }

  describe '#show?' do
    context 'when user is in the same family' do
      before do
        allow(owner).to receive(:family).and_return(family)
      end

      it 'allows family owner to view member details' do
        policy = Family::MembershipPolicy.new(owner, member_membership)

        expect(policy).to permit(:show)
      end

      it 'allows family owner to view their own membership' do
        policy = Family::MembershipPolicy.new(owner, owner_membership)

        expect(policy).to permit(:show)
      end

      it 'allows regular member to view other members' do
        allow(member).to receive(:family).and_return(family)
        policy = Family::MembershipPolicy.new(member, another_member_membership)

        expect(policy).to permit(:show)
      end

      it 'allows member to view their own membership' do
        allow(member).to receive(:family).and_return(family)
        policy = Family::MembershipPolicy.new(member, member_membership)

        expect(policy).to permit(:show)
      end
    end

    context 'when user is not in the same family' do
      it 'denies user from different family from viewing membership' do
        policy = Family::MembershipPolicy.new(other_user, member_membership)

        expect(policy).not_to permit(:show)
      end
    end

    context 'with unauthenticated user' do
      it 'denies unauthenticated user from viewing membership' do
        policy = Family::MembershipPolicy.new(nil, member_membership)

        expect(policy).not_to permit(:show)
      end
    end
  end

  describe '#update?' do
    context 'when user is updating their own membership' do
      it 'allows user to update their own membership settings' do
        allow(member).to receive(:family).and_return(family)
        policy = Family::MembershipPolicy.new(member, member_membership)

        expect(policy).to permit(:update)
      end

      it 'allows owner to update their own membership' do
        allow(owner).to receive(:family).and_return(family)
        policy = Family::MembershipPolicy.new(owner, owner_membership)

        expect(policy).to permit(:update)
      end
    end

    context 'when user is family owner' do
      before do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
      end

      it 'allows family owner to update other members settings' do
        policy = Family::MembershipPolicy.new(owner, member_membership)

        expect(policy).to permit(:update)
      end

      it 'allows family owner to update multiple members' do
        policy1 = Family::MembershipPolicy.new(owner, member_membership)
        policy2 = Family::MembershipPolicy.new(owner, another_member_membership)

        expect(policy1).to permit(:update)
        expect(policy2).to permit(:update)
      end
    end

    context 'when user is regular family member' do
      before do
        allow(member).to receive(:family).and_return(family)
        allow(member).to receive(:family_owner?).and_return(false)
      end

      it 'denies regular member from updating other members settings' do
        policy = Family::MembershipPolicy.new(member, another_member_membership)

        expect(policy).not_to permit(:update)
      end

      it 'denies regular member from updating owner settings' do
        policy = Family::MembershipPolicy.new(member, owner_membership)

        expect(policy).not_to permit(:update)
      end
    end

    context 'when user is not in the family' do
      it 'denies user from updating membership of different family' do
        policy = Family::MembershipPolicy.new(other_user, member_membership)

        expect(policy).not_to permit(:update)
      end
    end

    context 'with unauthenticated user' do
      it 'denies unauthenticated user from updating membership' do
        policy = Family::MembershipPolicy.new(nil, member_membership)

        expect(policy).not_to permit(:update)
      end
    end
  end

  describe '#destroy?' do
    context 'when user is removing themselves' do
      it 'allows user to remove their own membership (leave family)' do
        allow(member).to receive(:family).and_return(family)
        policy = Family::MembershipPolicy.new(member, member_membership)

        expect(policy).to permit(:destroy)
      end

      it 'allows owner to remove their own membership' do
        allow(owner).to receive(:family).and_return(family)
        policy = Family::MembershipPolicy.new(owner, owner_membership)

        expect(policy).to permit(:destroy)
      end
    end

    context 'when user is family owner' do
      before do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
      end

      it 'allows family owner to remove other members' do
        policy = Family::MembershipPolicy.new(owner, member_membership)

        expect(policy).to permit(:destroy)
      end

      it 'allows family owner to remove multiple members' do
        policy1 = Family::MembershipPolicy.new(owner, member_membership)
        policy2 = Family::MembershipPolicy.new(owner, another_member_membership)

        expect(policy1).to permit(:destroy)
        expect(policy2).to permit(:destroy)
      end
    end

    context 'when user is regular family member' do
      before do
        allow(member).to receive(:family).and_return(family)
        allow(member).to receive(:family_owner?).and_return(false)
      end

      it 'denies regular member from removing other members' do
        policy = Family::MembershipPolicy.new(member, another_member_membership)

        expect(policy).not_to permit(:destroy)
      end

      it 'denies regular member from removing owner' do
        policy = Family::MembershipPolicy.new(member, owner_membership)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'when user is not in the family' do
      it 'denies user from removing membership of different family' do
        policy = Family::MembershipPolicy.new(other_user, member_membership)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'with unauthenticated user' do
      it 'denies unauthenticated user from removing membership' do
        policy = Family::MembershipPolicy.new(nil, member_membership)

        expect(policy).not_to permit(:destroy)
      end
    end
  end

  describe 'edge cases' do
    context 'when membership belongs to different family' do
      let(:other_family) { create(:family) }
      let(:other_family_owner) { other_family.creator }
      let(:other_family_membership) do
        create(:family_membership, :owner, family: other_family, user: other_family_owner)
      end

      before do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
      end

      it 'denies owner from viewing membership of different family' do
        policy = Family::MembershipPolicy.new(owner, other_family_membership)

        expect(policy).not_to permit(:show)
      end

      it 'denies owner from updating membership of different family' do
        policy = Family::MembershipPolicy.new(owner, other_family_membership)

        expect(policy).not_to permit(:update)
      end

      it 'denies owner from destroying membership of different family' do
        policy = Family::MembershipPolicy.new(owner, other_family_membership)

        expect(policy).not_to permit(:destroy)
      end
    end

    context 'when owner tries to modify another owners membership' do
      let(:co_owner) { create(:user) }
      let(:co_owner_membership) { create(:family_membership, :owner, family: family, user: co_owner) }

      before do
        allow(owner).to receive(:family).and_return(family)
        allow(owner).to receive(:family_owner?).and_return(true)
      end

      it 'allows owner to view another owner' do
        policy = Family::MembershipPolicy.new(owner, co_owner_membership)

        expect(policy).to permit(:show)
      end

      it 'allows owner to update another owner (family owner has full control)' do
        policy = Family::MembershipPolicy.new(owner, co_owner_membership)

        expect(policy).to permit(:update)
      end

      it 'allows owner to remove another owner (family owner has full control)' do
        policy = Family::MembershipPolicy.new(owner, co_owner_membership)

        expect(policy).to permit(:destroy)
      end
    end
  end

  describe 'authorization consistency' do
    it 'ensures owner can view, update, and destroy all memberships in their family' do
      allow(owner).to receive(:family).and_return(family)
      allow(owner).to receive(:family_owner?).and_return(true)

      policy = Family::MembershipPolicy.new(owner, member_membership)

      expect(policy).to permit(:show)
      expect(policy).to permit(:update)
      expect(policy).to permit(:destroy)
    end

    it 'ensures regular members can only manage their own membership' do
      allow(member).to receive(:family).and_return(family)
      allow(member).to receive(:family_owner?).and_return(false)

      own_policy = Family::MembershipPolicy.new(member, member_membership)
      other_policy = Family::MembershipPolicy.new(member, another_member_membership)

      # Can manage own membership
      expect(own_policy).to permit(:show)
      expect(own_policy).to permit(:update)
      expect(own_policy).to permit(:destroy)

      # Can view but not manage others
      expect(other_policy).to permit(:show)
      expect(other_policy).not_to permit(:update)
      expect(other_policy).not_to permit(:destroy)
    end

    it 'ensures users can always leave the family (remove own membership)' do
      allow(member).to receive(:family).and_return(family)
      policy = Family::MembershipPolicy.new(member, member_membership)

      expect(policy).to permit(:destroy)
    end
  end
end
