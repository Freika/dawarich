# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family Memberships', type: :request do
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

  describe 'GET /families/:family_id/members' do
    it 'shows all family members' do
      get "/families/#{family.id}/members"
      expect(response).to have_http_status(:ok)
    end

    context 'when user is not in the family' do
      let(:outsider) { create(:user) }

      before { sign_in outsider }

      it 'redirects to families index' do
        get "/families/#{family.id}/members"
        expect(response).to redirect_to(families_path)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to login' do
        get "/families/#{family.id}/members"
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'GET /families/:family_id/members/:id' do
    it 'shows a specific membership' do
      get "/families/#{family.id}/members/#{member_membership.id}"
      expect(response).to have_http_status(:ok)
    end

    context 'when membership does not belong to the family' do
      let(:other_family) { create(:family) }
      let(:other_membership) { create(:family_membership, family: other_family) }

      it 'returns not found' do
        get "/families/#{family.id}/members/#{other_membership.id}"
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when user is not in the family' do
      let(:outsider) { create(:user) }

      before { sign_in outsider }

      it 'redirects to families index' do
        get "/families/#{family.id}/members/#{member_membership.id}"
        expect(response).to redirect_to(families_path)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to login' do
        get "/families/#{family.id}/members/#{member_membership.id}"
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'DELETE /families/:family_id/members/:id' do
    context 'when removing a regular member' do
      it 'removes the member from the family' do
        expect do
          delete "/families/#{family.id}/members/#{member_membership.id}"
        end.to change(FamilyMembership, :count).by(-1)
      end

      it 'redirects with success message' do
        member_email = member_user.email
        delete "/families/#{family.id}/members/#{member_membership.id}"
        expect(response).to redirect_to(family_path(family))
        follow_redirect!
        expect(response.body).to include("#{member_email} has been removed from the family")
      end

      it 'removes the user from the family' do
        delete "/families/#{family.id}/members/#{member_membership.id}"
        expect(member_user.reload.family).to be_nil
      end
    end

    context 'when trying to remove the owner while other members exist' do
      it 'does not remove the owner' do
        expect do
          delete "/families/#{family.id}/members/#{owner_membership.id}"
        end.not_to change(FamilyMembership, :count)
      end

      it 'redirects with error message' do
        delete "/families/#{family.id}/members/#{owner_membership.id}"
        expect(response).to redirect_to(family_path(family))
        follow_redirect!
        expect(response.body).to include('Cannot remove family owner while other members exist')
      end
    end

    context 'when owner is the only member' do
      before { member_membership.destroy! }

      it 'allows removing the owner' do
        expect do
          delete "/families/#{family.id}/members/#{owner_membership.id}"
        end.to change(FamilyMembership, :count).by(-1)
      end

      it 'redirects with success message' do
        user_email = user.email
        delete "/families/#{family.id}/members/#{owner_membership.id}"
        expect(response).to redirect_to(family_path(family))
        follow_redirect!
        expect(response.body).to include("#{user_email} has been removed from the family")
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
        delete "/families/#{family.id}/members/#{member_membership.id}"
        expect(response).to redirect_to(families_path)
      end
    end

    context 'when not authenticated' do
      before { sign_out user }

      it 'redirects to login' do
        delete "/families/#{family.id}/members/#{member_membership.id}"
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'authorization for different member roles' do
    context 'when member tries to remove another member' do
      before { sign_in member_user }

      it 'returns forbidden' do
        delete "/families/#{family.id}/members/#{owner_membership.id}"
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'when member views another member' do
      before { sign_in member_user }

      it 'allows viewing membership' do
        get "/families/#{family.id}/members/#{owner_membership.id}"
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when member views members list' do
      before { sign_in member_user }

      it 'allows viewing members list' do
        get "/families/#{family.id}/members"
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe 'member removal workflow' do
    it 'removes member and updates family associations' do
      # Verify initial state
      expect(family.members).to include(user, member_user)
      expect(member_user.family).to eq(family)

      # Remove member
      delete "/families/#{family.id}/members/#{member_membership.id}"

      # Verify removal
      expect(response).to redirect_to(family_path(family))
      expect(family.reload.members).to include(user)
      expect(family.members).not_to include(member_user)
      expect(member_user.reload.family).to be_nil
    end

    it 'prevents removing owner when family has members' do
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

    it 'allows removing owner when they are the only member' do
      # Remove other member first
      member_membership.destroy!

      # Verify only owner remains
      expect(family.reload.members.count).to eq(1)
      expect(family.members).to include(user)

      # Remove owner
      expect do
        delete "/families/#{family.id}/members/#{owner_membership.id}"
      end.to change(FamilyMembership, :count).by(-1)

      expect(response).to redirect_to(family_path(family))
      expect(user.reload.family).to be_nil
    end
  end
end
