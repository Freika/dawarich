# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, 'family methods', type: :model do
  let(:user) { create(:user) }

  describe 'family associations' do
    it { is_expected.to have_one(:family_membership).dependent(:destroy) }
    it { is_expected.to have_one(:family).through(:family_membership) }
    it {
      is_expected.to have_many(:created_families).class_name('Family').with_foreign_key('creator_id').dependent(:destroy)
    }
    it {
      is_expected.to have_many(:sent_family_invitations).class_name('FamilyInvitation').with_foreign_key('invited_by_id').dependent(:destroy)
    }
  end

  describe '#in_family?' do
    context 'when user has no family membership' do
      it 'returns false' do
        expect(user.in_family?).to be false
      end
    end

    context 'when user has family membership' do
      let(:family) { create(:family, creator: user) }

      before do
        create(:family_membership, user: user, family: family)
      end

      it 'returns true' do
        expect(user.in_family?).to be true
      end
    end
  end

  describe '#family_owner?' do
    let(:family) { create(:family, creator: user) }

    context 'when user is family owner' do
      before do
        create(:family_membership, user: user, family: family, role: :owner)
      end

      it 'returns true' do
        expect(user.family_owner?).to be true
      end
    end

    context 'when user is family member' do
      before do
        create(:family_membership, user: user, family: family, role: :member)
      end

      it 'returns false' do
        expect(user.family_owner?).to be false
      end
    end

    context 'when user has no family membership' do
      it 'returns false' do
        expect(user.family_owner?).to be false
      end
    end
  end

  describe '#can_delete_account?' do
    context 'when user is not a family owner' do
      it 'returns true' do
        expect(user.can_delete_account?).to be true
      end
    end

    context 'when user is family owner with only themselves as member' do
      let(:family) { create(:family, creator: user) }

      before do
        create(:family_membership, user: user, family: family, role: :owner)
      end

      it 'returns true' do
        expect(user.can_delete_account?).to be true
      end
    end

    context 'when user is family owner with other members' do
      let(:family) { create(:family, creator: user) }
      let(:other_user) { create(:user) }

      before do
        create(:family_membership, user: user, family: family, role: :owner)
        create(:family_membership, user: other_user, family: family, role: :member)
      end

      it 'returns false' do
        expect(user.can_delete_account?).to be false
      end
    end
  end

  describe 'dependent destroy behavior' do
    let(:family) { create(:family, creator: user) }

    context 'when user has created families' do
      it 'prevents deletion when family has members' do
        other_user = create(:user)
        create(:family_membership, user: user, family: family, role: :owner)
        create(:family_membership, user: other_user, family: family, role: :member)

        expect(user.can_delete_account?).to be false
      end
    end

    context 'when user has sent invitations' do
      before do
        create(:family_invitation, family: family, invited_by: user)
      end

      it 'destroys associated invitations when user is destroyed' do
        expect { user.destroy }.to change(FamilyInvitation, :count).by(-1)
      end
    end

    context 'when user has family membership' do
      before do
        create(:family_membership, user: user, family: family)
      end

      it 'destroys associated membership when user is destroyed' do
        expect { user.destroy }.to change(FamilyMembership, :count).by(-1)
      end
    end
  end
end
