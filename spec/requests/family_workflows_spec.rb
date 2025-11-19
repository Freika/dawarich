# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family Workflows', type: :request do
  let(:user1) { create(:user, email: 'alice@example.com') }
  let(:user2) { create(:user, email: 'bob@example.com') }
  let(:user3) { create(:user, email: 'charlie@example.com') }



  describe 'Complete family creation and management workflow' do
    it 'allows creating a family, inviting members, and managing the family' do
      # Step 1: User1 creates a family
      sign_in user1

      get '/family/new'
      expect(response).to have_http_status(:ok)

      post '/family', params: { family: { name: 'The Smith Family' } }

      # The redirect should be to the newly created family
      expect(response).to have_http_status(:found)
      family = Family.find_by(name: 'The Smith Family')
      expect(family).to be_present
      expect(family.name).to eq('The Smith Family')
      expect(family.creator).to eq(user1)
      expect(user1.reload.family).to eq(family)
      expect(user1.family_owner?).to be true

      # Step 2: User1 invites User2
      post "/family/invitations", params: {
        family_invitation: { email: user2.email }
      }
      expect(response).to redirect_to(family_path)

      invitation = family.family_invitations.find_by(email: user2.email)
      expect(invitation).to be_present
      expect(invitation.email).to eq(user2.email)
      expect(invitation.family).to eq(family)
      expect(invitation.pending?).to be true

      # Step 3: User2 views and accepts invitation
      sign_out user1

      # Public invitation view (no auth required)
      get "/invitations/#{invitation.token}"
      expect(response).to have_http_status(:ok)

      # User2 accepts invitation
      sign_in user2
      post accept_family_invitation_path(token: invitation.token)
      expect(response).to redirect_to(family_path)

      expect(user2.reload.family).to eq(family)
      expect(user2.family_owner?).to be false
      expect(invitation.reload.accepted?).to be true

      # Step 4: User1 invites User3
      sign_in user1
      post "/family/invitations", params: {
        family_invitation: { email: user3.email }
      }

      invitation2 = family.family_invitations.find_by(email: user3.email)
      expect(invitation2).to be_present
      expect(invitation2.email).to eq(user3.email)

      # Step 5: User3 accepts invitation
      sign_in user3
      post accept_family_invitation_path(token: invitation2.token)

      expect(user3.reload.family).to eq(family)
      expect(family.reload.members.count).to eq(3)

      # Step 6: Family owner views members on family show page
      sign_in user1
      get "/family"
      expect(response).to have_http_status(:ok)

      # Step 7: Owner removes a member
      delete "/family/members/#{user2.family_membership.id}"
      expect(response).to redirect_to(family_path)

      expect(user2.reload.family).to be_nil
      expect(family.reload.members.count).to eq(2)
      expect(family.members).to include(user1, user3)
      expect(family.members).not_to include(user2)
    end
  end

  describe 'Family invitation expiration workflow' do
    let(:family) { create(:family, name: 'Test Family', creator: user1) }
    let!(:owner_membership) { create(:family_membership, user: user1, family: family, role: :owner) }
    let!(:invitation) do
      create(:family_invitation, family: family, email: user2.email, invited_by: user1, expires_at: 1.day.ago)
    end

    it 'handles expired invitations correctly' do
      # User2 tries to view expired invitation
      get "/invitations/#{invitation.token}"
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include('This invitation has expired')

      # User2 tries to accept expired invitation
      sign_in user2
      post accept_family_invitation_path(token: invitation.token)
      expect(response).to redirect_to(root_path)

      expect(user2.reload.family).to be_nil
      expect(invitation.reload.pending?).to be true
    end
  end

  describe 'Multiple family membership prevention workflow' do
    let(:family1) { create(:family, name: 'Family 1', creator: user1) }
    let(:family2) { create(:family, name: 'Family 2', creator: user2) }
    let!(:user1_membership) { create(:family_membership, user: user1, family: family1, role: :owner) }
    let!(:user2_membership) { create(:family_membership, user: user2, family: family2, role: :owner) }
    let!(:invitation1) { create(:family_invitation, family: family1, email: user3.email, invited_by: user1) }
    let!(:invitation2) { create(:family_invitation, family: family2, email: user3.email, invited_by: user2) }

    it 'prevents users from joining multiple families' do
      # User3 accepts invitation to Family 1
      sign_in user3
      post accept_family_invitation_path(token: invitation1.token)
      expect(response).to redirect_to(family_path)
      expect(user3.family).to eq(family1)

      # User3 tries to accept invitation to Family 2
      post accept_family_invitation_path(token: invitation2.token)
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to include('You must leave your current family')

      expect(user3.reload.family).to eq(family1) # Still in first family
    end
  end

  describe 'Family ownership transfer and leaving workflow' do
    let(:family) { create(:family, creator: user1) }
    let!(:owner_membership) { create(:family_membership, user: user1, family: family, role: :owner) }
    let!(:member_membership) { create(:family_membership, user: user2, family: family, role: :member) }

    it 'prevents owner from leaving when members exist' do
      sign_in user1

      # Owner tries to leave family with members (using memberships destroy route)
      owner_membership = user1.family_membership
      delete "/family/members/#{owner_membership.id}"
      expect(response).to redirect_to(family_path)
      follow_redirect!
      expect(response.body).to include('cannot remove their own membership')

      expect(user1.reload.family).to eq(family)
      expect(user1.family_owner?).to be true
    end

    it 'allows owner to leave when they are the only member' do
      sign_in user1

      # Remove the member first
      delete "/family/members/#{member_membership.id}"

      # Owner cannot leave even when alone - they must delete the family instead
      owner_membership = user1.reload.family_membership
      delete "/family/members/#{owner_membership.id}"
      expect(response).to redirect_to(family_path)
      follow_redirect!
      expect(response.body).to include('cannot remove their own membership')

      expect(user1.reload.family).to eq(family)
    end

    it 'allows members to leave freely' do
      sign_in user2

      delete "/family/members/#{member_membership.id}"
      expect(response).to redirect_to(new_family_path)

      expect(user2.reload.family).to be_nil
      expect(family.reload.members.count).to eq(1)
      expect(family.members).to include(user1)
      expect(family.members).not_to include(user2)
    end
  end

  describe 'Family deletion workflow' do
    let(:family) { create(:family, creator: user1) }
    let!(:owner_membership) { create(:family_membership, user: user1, family: family, role: :owner) }

    context 'when members exist' do
      let!(:member_membership) { create(:family_membership, user: user2, family: family, role: :member) }

      it 'prevents family deletion when members exist' do
        sign_in user1

        expect do
          delete "/family"
        end.not_to change(Family, :count)

        expect(response).to redirect_to(family_path)
        follow_redirect!
        expect(response.body).to include('Cannot delete family with members')
      end
    end

    it 'allows family deletion when owner is the only member' do
      sign_in user1

      expect do
        delete "/family"
      end.to change(Family, :count).by(-1)

      expect(response).to redirect_to(new_family_path)
      expect(user1.reload.family).to be_nil
    end
  end

  describe 'Authorization workflow' do
    let(:family) { create(:family, creator: user1) }
    let!(:owner_membership) { create(:family_membership, user: user1, family: family, role: :owner) }
    let!(:member_membership) { create(:family_membership, user: user2, family: family, role: :member) }

    it 'enforces proper authorization for family management' do
      # Member cannot invite others
      sign_in user2
      post "/family/invitations", params: {
        family_invitation: { email: user3.email }
      }
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include('not authorized')

      # Member cannot remove other members
      delete "/family/members/#{owner_membership.id}"
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include('not authorized')

      # Member cannot edit family
      patch "/family", params: { family: { name: 'Hacked Family' } }
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include('not authorized')

      # Member cannot delete family
      delete "/family"
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include('not authorized')

      # Outsider cannot access family
      sign_in user3
      get "/family"
      expect(response).to redirect_to(new_family_path)
    end
  end

  describe 'Email invitation workflow' do
    let(:family) { create(:family, name: 'Test Family', creator: user1) }
    let!(:owner_membership) { create(:family_membership, user: user1, family: family, role: :owner) }

    it 'handles invitation emails correctly' do
      sign_in user1

      # Mock email delivery
      expect do
        post "/family/invitations", params: {
          family_invitation: { email: 'newuser@example.com' }
        }
      end.to change(Family::Invitation, :count).by(1)

      invitation = family.family_invitations.find_by(email: 'newuser@example.com')
      expect(invitation.email).to eq('newuser@example.com')
      expect(invitation.token).to be_present
      expect(invitation.expires_at).to be > Time.current
    end
  end

  describe 'Navigation and redirect workflow' do
    it 'handles proper redirects for family-related navigation' do
      # User without family can access new family page
      sign_in user1
      get '/family/new'
      expect(response).to have_http_status(:ok)

      # User creates family
      post '/family', params: { family: { name: 'Test Family' } }
      expect(response).to have_http_status(:found)

      # User with family can view their family
      get '/family'
      expect(response).to have_http_status(:ok)

      # User with family gets redirected from new family page
      get '/family/new'
      expect(response).to redirect_to(family_path)
    end
  end
end
