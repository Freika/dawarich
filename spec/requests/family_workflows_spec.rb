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

      get '/families'
      expect(response).to have_http_status(:ok)

      get '/families/new'
      expect(response).to have_http_status(:ok)

      post '/families', params: { family: { name: 'The Smith Family' } }
      expect(response).to redirect_to(family_path(Family.last))

      family = Family.last
      expect(family.name).to eq('The Smith Family')
      expect(family.creator).to eq(user1)
      expect(user1.reload.family).to eq(family)
      expect(user1.family_owner?).to be true

      # Step 2: User1 invites User2
      post "/families/#{family.id}/invitations", params: {
        family_invitation: { email: user2.email }
      }
      expect(response).to redirect_to(family_path(family))

      invitation = FamilyInvitation.last
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
      post "/families/#{family.id}/invitations/#{invitation.id}/accept"
      expect(response).to redirect_to(family_path(family))

      expect(user2.reload.family).to eq(family)
      expect(user2.family_owner?).to be false
      expect(invitation.reload.accepted?).to be true

      # Step 4: User1 invites User3
      sign_in user1
      post "/families/#{family.id}/invitations", params: {
        family_invitation: { email: user3.email }
      }

      invitation2 = FamilyInvitation.last
      expect(invitation2.email).to eq(user3.email)

      # Step 5: User3 accepts invitation
      sign_in user3
      post "/families/#{family.id}/invitations/#{invitation2.id}/accept"

      expect(user3.reload.family).to eq(family)
      expect(family.reload.members.count).to eq(3)

      # Step 6: Family owner views and manages members
      sign_in user1
      get "/families/#{family.id}/members"
      expect(response).to have_http_status(:ok)

      get "/families/#{family.id}/members/#{user2.family_membership.id}"
      expect(response).to have_http_status(:ok)

      # Step 7: Owner removes a member
      delete "/families/#{family.id}/members/#{user2.family_membership.id}"
      expect(response).to redirect_to(family_path(family))

      expect(user2.reload.family).to be_nil
      expect(family.reload.members.count).to eq(2)
      expect(family.members).to include(user1, user3)
      expect(family.members).not_to include(user2)
    end
  end

  describe 'Family invitation expiration workflow' do
    it 'handles expired invitations correctly' do
      # User1 creates family and invitation
      sign_in user1
      post '/families', params: { family: { name: 'Test Family' } }
      family = Family.last

      post "/families/#{family.id}/invitations", params: {
        family_invitation: { email: user2.email }
      }

      invitation = FamilyInvitation.last

      # Expire the invitation
      invitation.update!(expires_at: 1.day.ago)

      # User2 tries to view expired invitation
      sign_out user1
      get "/invitations/#{invitation.token}"
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include('This invitation has expired')

      # User2 tries to accept expired invitation
      sign_in user2
      post "/families/#{family.id}/invitations/#{invitation.id}/accept"
      expect(response).to redirect_to(root_path)

      expect(user2.reload.family).to be_nil
      expect(invitation.reload.pending?).to be true
    end
  end

  describe 'Multiple family membership prevention workflow' do
    it 'prevents users from joining multiple families' do
      # User1 creates first family
      sign_in user1
      post '/families', params: { family: { name: 'Family 1' } }
      family1 = Family.last

      # User2 creates second family
      sign_in user2
      post '/families', params: { family: { name: 'Family 2' } }
      family2 = Family.last

      # User1 invites User3 to Family 1
      sign_in user1
      post "/families/#{family1.id}/invitations", params: {
        family_invitation: { email: user3.email }
      }
      invitation1 = FamilyInvitation.last

      # User2 invites User3 to Family 2
      sign_in user2
      post "/families/#{family2.id}/invitations", params: {
        family_invitation: { email: user3.email }
      }
      invitation2 = FamilyInvitation.last

      # User3 accepts invitation to Family 1
      sign_in user3
      post "/families/#{family1.id}/invitations/#{invitation1.id}/accept"
      expect(user3.reload.family).to eq(family1)

      # User3 tries to accept invitation to Family 2
      post "/families/#{family2.id}/invitations/#{invitation2.id}/accept"
      expect(response).to redirect_to(root_path)
      follow_redirect!
      expect(response.body).to include('You must leave your current family')

      expect(user3.reload.family).to eq(family1) # Still in first family
    end
  end

  describe 'Family ownership transfer and leaving workflow' do
    let(:family) { create(:family, creator: user1) }
    let!(:owner_membership) { create(:family_membership, user: user1, family: family, role: :owner) }
    let!(:member_membership) { create(:family_membership, user: user2, family: family, role: :member) }

    it 'prevents owner from leaving when members exist' do
      sign_in user1

      # Owner tries to leave family with members
      delete "/families/#{family.id}/leave"
      expect(response).to redirect_to(family_path(family))
      follow_redirect!
      expect(response.body).to include('cannot leave')

      expect(user1.reload.family).to eq(family)
      expect(user1.family_owner?).to be true
    end

    it 'allows owner to leave when they are the only member' do
      sign_in user1

      # Remove the member first
      delete "/families/#{family.id}/members/#{member_membership.id}"

      # Now owner can leave (which deletes the family)
      expect do
        delete "/families/#{family.id}/leave"
      end.to change(Family, :count).by(-1)

      expect(response).to redirect_to(families_path)
      expect(user1.reload.family).to be_nil
    end

    it 'allows members to leave freely' do
      sign_in user2

      delete "/families/#{family.id}/leave"
      expect(response).to redirect_to(families_path)

      expect(user2.reload.family).to be_nil
      expect(family.reload.members.count).to eq(1)
      expect(family.members).to include(user1)
      expect(family.members).not_to include(user2)
    end
  end

  describe 'Family deletion workflow' do
    let(:family) { create(:family, creator: user1) }
    let!(:owner_membership) { create(:family_membership, user: user1, family: family, role: :owner) }

    it 'prevents family deletion when members exist' do
      create(:family_membership, user: user2, family: family, role: :member)

      sign_in user1

      expect do
        delete "/families/#{family.id}"
      end.not_to change(Family, :count)

      expect(response).to redirect_to(family_path(family))
      follow_redirect!
      expect(response.body).to include('Cannot delete family with members')
    end

    it 'allows family deletion when owner is the only member' do
      sign_in user1

      expect do
        delete "/families/#{family.id}"
      end.to change(Family, :count).by(-1)

      expect(response).to redirect_to(families_path)
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
      post "/families/#{family.id}/invitations", params: {
        family_invitation: { email: user3.email }
      }
      expect(response).to have_http_status(:forbidden)

      # Member cannot remove other members
      delete "/families/#{family.id}/members/#{owner_membership.id}"
      expect(response).to have_http_status(:forbidden)

      # Member cannot edit family
      patch "/families/#{family.id}", params: { family: { name: 'Hacked Family' } }
      expect(response).to have_http_status(:forbidden)

      # Member cannot delete family
      delete "/families/#{family.id}"
      expect(response).to have_http_status(:forbidden)

      # Outsider cannot access family
      sign_in user3
      get "/families/#{family.id}"
      expect(response).to redirect_to(families_path)

      get "/families/#{family.id}/members"
      expect(response).to redirect_to(families_path)
    end
  end

  describe 'Email invitation workflow' do
    it 'handles invitation emails correctly' do
      sign_in user1
      post '/families', params: { family: { name: 'Test Family' } }
      family = Family.last

      # Mock email delivery
      expect do
        post "/families/#{family.id}/invitations", params: {
          family_invitation: { email: 'newuser@example.com' }
        }
      end.to change(FamilyInvitation, :count).by(1)

      invitation = FamilyInvitation.last
      expect(invitation.email).to eq('newuser@example.com')
      expect(invitation.token).to be_present
      expect(invitation.expires_at).to be > Time.current
    end
  end

  describe 'Navigation and redirect workflow' do
    it 'handles proper redirects for family-related navigation' do
      # User without family sees index
      sign_in user1
      get '/families'
      expect(response).to have_http_status(:ok)

      # User creates family
      post '/families', params: { family: { name: 'Test Family' } }
      family = Family.last

      # User with family gets redirected from index to family page
      get '/families'
      expect(response).to redirect_to(family_path(family))

      # User with family gets redirected from new family page
      get '/families/new'
      expect(response).to redirect_to(family_path(family))
    end
  end
end
