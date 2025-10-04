# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family::Memberships', type: :request do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
  let(:member_user) { create(:user) }
  let!(:member_membership) { create(:family_membership, user: member_user, family: family, role: :member) }

  before do
    stub_request(:any, 'https://api.github.com/repos/Freika/dawarich/tags')
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
    sign_in user
  end

  describe 'DELETE /families/:family_id/members/:id' do
    context 'when removing a regular member' do
      it 'removes the member from the family' do
        expect do
          delete "/family/members/#{member_membership.id}"
        end.to change(FamilyMembership, :count).by(-1)
      end

      it 'redirects with success message' do
        member_email = member_user.email
        delete "/family/members/#{member_membership.id}"
        expect(response).to redirect_to(family_path)
        follow_redirect!
        expect(response.body).to include("#{member_email} has been removed from the family")
      end

      it 'removes the user from the family' do
        delete "/family/members/#{member_membership.id}"
        expect(member_user.reload.family).to be_nil
      end
    end

    context 'when trying to remove the owner' do
      it 'does not remove the owner' do
        expect do
          delete "/family/members/#{owner_membership.id}"
        end.not_to change(FamilyMembership, :count)
      end

      it 'redirects with error message explaining owners must delete family' do
        delete "/family/members/#{owner_membership.id}"
        expect(response).to redirect_to(family_path)
        follow_redirect!
        expect(response.body).to include('Family owners cannot remove their own membership. To leave the family, delete it instead.')
      end

      it 'prevents owner removal even when they are the only member' do
        member_membership.destroy!

        expect do
          delete "/family/members/#{owner_membership.id}"
        end.not_to change(FamilyMembership, :count)

        expect(response).to redirect_to(family_path)
        follow_redirect!
        expect(response.body).to include('Family owners cannot remove their own membership')
      end
    end

    context 'when membership does not belong to the family' do
      let(:other_family) { create(:family) }
      let(:other_membership) { create(:family_membership, family: other_family) }

      it 'returns not found' do
        delete "/families/#{family.id}/members/#{other_membership.id}"
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when user is not in the family' do
      let(:outsider) { create(:user) }

      before { sign_in outsider }

      it 'redirects to families index' do
        delete "/family/members/#{member_membership.id}"
        expect(response).to redirect_to(new_family_path)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to login' do
        delete "/family/members/#{member_membership.id}"
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'authorization for different member roles' do
    context 'when member tries to remove another member' do
      before { sign_in member_user }

      it 'returns forbidden' do
        delete "/family/members/#{owner_membership.id}"
        expect(response).to have_http_status(:see_other)
        expect(flash[:alert]).to include('not authorized')
      end
    end

  end

  describe 'member removal workflow' do
    it 'removes member and updates family associations' do
      # Verify initial state
      expect(family.members).to include(user, member_user)
      expect(member_user.family).to eq(family)

      # Remove member
      delete "/family/members/#{member_membership.id}"

      # Verify removal
      expect(response).to redirect_to(family_path(family))
      expect(family.reload.members).to include(user)
      expect(family.members).not_to include(member_user)
      expect(member_user.reload.family).to be_nil
    end

    it 'prevents removing owner regardless of member count' do
      # Verify initial state
      expect(family.members.count).to eq(2)
      expect(user.family_owner?).to be true

      # Try to remove owner
      delete "/families/#{family.id}/members/#{owner_membership.id}"

      # Verify prevention
      expect(response).to redirect_to(family_path(family))
      expect(family.reload.members).to include(user, member_user)
      expect(user.reload.family).to eq(family)
    end

    it 'prevents removing owner even when they are the only member' do
      # Remove other member first
      member_membership.destroy!

      # Verify only owner remains
      expect(family.reload.members.count).to eq(1)
      expect(family.members).to include(user)

      # Try to remove owner - should be prevented
      expect do
        delete "/family/members/#{owner_membership.id}"
      end.not_to change(FamilyMembership, :count)

      expect(response).to redirect_to(family_path(family))
      expect(user.reload.family).to eq(family)
      expect(family.reload).to be_present
    end

    it 'requires owners to use family deletion to leave the family' do
      member_membership.destroy!

      delete "/family/members/#{owner_membership.id}"
      expect(response).to redirect_to(family_path)
      expect(flash[:alert]).to include('Family owners cannot remove their own membership')

      delete "/family"
      expect(response).to redirect_to(new_family_path)
      expect(user.reload.family).to be_nil
    end
  end
end
