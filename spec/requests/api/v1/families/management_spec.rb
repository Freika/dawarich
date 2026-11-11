# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family management API', type: :request do
  let(:owner) { create(:user) }
  let(:member) { create(:user) }
  let(:outsider) { create(:user) }
  let(:family) { create(:family, creator: owner) }
  let!(:ownership) { create(:family_membership, user: owner, family: family, role: :owner) }
  let!(:membership) { create(:family_membership, user: member, family: family) }

  def headers(user)
    { 'Authorization' => "Bearer #{user.api_key}" }
  end

  def payload
    response.parsed_body
  end

  shared_examples 'family management' do |self_hosted|
    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(self_hosted)
      owner.update!(plan: :family, status: :active, active_until: 1.month.from_now) unless self_hosted
    end

    it 'requires API authentication' do
      get '/api/v1/families/manage'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns owner management data without sharing location or history' do
      get '/api/v1/families/manage', headers: headers(owner)

      expect(response).to have_http_status(:ok)
      expect(payload.dig('family', 'id')).to eq(family.id)
      expect(payload.dig('me', 'membership_id')).to eq(ownership.id)
      expect(payload['members'].pluck('id')).to contain_exactly(ownership.id, membership.id)
      expect(payload.dig('capacity', 'limit')).to eq(self_hosted ? nil : 5)
      expect(payload.dig('capacity', 'members')).to eq(2)
      expect(payload).not_to have_key('locations')
      expect(payload).not_to have_key('location_requests')
    end

    it 'does not expose the owner roster to a member' do
      get '/api/v1/families/manage', headers: headers(member)

      expect(response).to have_http_status(:ok)
      expect(payload['members'].pluck('user_id')).to eq([member.id])
    end

    it 'returns an empty management state before family creation' do
      get '/api/v1/families/manage', headers: headers(outsider)

      expect(response).to have_http_status(:ok)
      expect(payload['family']).to be_nil
      expect(payload['me']).to be_nil
      expect(payload['members']).to eq([])
    end

    it 'renames the family as owner while ignoring ownership parameters' do
      patch '/api/v1/families/manage', params: { family: { name: 'New name', creator_id: outsider.id } },
                                           headers: headers(owner), as: :json

      expect(response).to have_http_status(:ok)
      expect(family.reload.name).to eq('New name')
      expect(family.creator_id).to eq(owner.id)
    end

    it 'rejects a member attempting to rename the family' do
      patch '/api/v1/families/manage', params: { family: { name: 'Changed' } },
                                           headers: headers(member), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(family.reload.name).not_to eq('Changed')
    end

    it 'returns JSON for malformed parameter wrappers' do
      patch '/api/v1/families/manage', params: { family: 'wrong shape' }, headers: headers(owner), as: :json

      expect(response).to have_http_status(:bad_request)
      expect(payload['error']).to eq('parameter_missing')
    end

    it 'rejects a blank family name' do
      patch '/api/v1/families/manage', params: { family: { name: '' } }, headers: headers(owner), as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'keeps cleanup available with the family feature disabled' do
      owner.update!(settings: owner.settings.merge('family_enabled' => false))
      delete "/api/v1/families/members/#{membership.id}", headers: headers(owner)

      expect(response).to have_http_status(:no_content)
      delete '/api/v1/families/manage', headers: headers(owner)
      expect(response).to have_http_status(:no_content)
    end

    it 'sends and revokes an invitation without enabling sharing' do
      post '/api/v1/families/invitations', params: { family_invitation: { email: outsider.email } },
                                         headers: headers(owner), as: :json

      expect(response).to have_http_status(:created)
      token = payload.dig('invitation', 'token')
      invitation = Family::Invitation.find_by!(token: token)
      expect(invitation.email).to eq(outsider.email)
      expect(outsider.reload.family_sharing_enabled?).to be false

      delete "/api/v1/families/invitations/#{token}", headers: headers(owner)

      expect(response).to have_http_status(:no_content)
      expect(invitation.reload).to be_cancelled
    end

    it 'rejects malformed invitation email without creating a reservation' do
      expect do
        post '/api/v1/families/invitations', params: { family_invitation: { email: 'invalid' } },
                                           headers: headers(owner), as: :json
      end.not_to change(Family::Invitation, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'prevents members from listing or creating invitations' do
      get '/api/v1/families/invitations', headers: headers(member)
      expect(response).to have_http_status(:forbidden)

      post '/api/v1/families/invitations', params: { family_invitation: { email: outsider.email } },
                                         headers: headers(member), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it 'hides invitation details from unrelated users even with the token' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: member.email)

      get "/api/v1/families/invitations/#{invitation.token}", headers: headers(outsider)

      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to include(invitation.email)
    end

    it 'accepts a matching invitation before membership without enabling location sharing' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: outsider.email)

      post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)

      expect(response).to have_http_status(:ok)
      expect(outsider.reload.family).to eq(family)
      expect(invitation.reload).to be_accepted
      expect(outsider.family_sharing_enabled?).to be false
    end

    it 'rejects repeated acceptance without duplicating membership' do
      invitation = create(:family_invitation, family: family, invited_by: owner, email: outsider.email)
      post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)
      expect(response).to have_http_status(:ok)

      expect do
        post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)
      end.not_to change(Family::Membership, :count)
      expect(response).to have_http_status(:forbidden)
    end

    it 'reports an expired invitation as unavailable and refuses acceptance' do
      invitation = create(:family_invitation, :with_expired_date, family: family,
                                                                invited_by: owner, email: outsider.email)
      get "/api/v1/families/invitations/#{invitation.token}", headers: headers(outsider)
      expect(response).to have_http_status(:ok)
      expect(payload.dig('invitation', 'acceptance_available')).to be false

      post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)
      expect(response).to have_http_status(:forbidden)
      expect(outsider.reload.family).to be_nil
    end

    it 'lets a member leave and cleans up their membership' do
      delete '/api/v1/families/membership', headers: headers(member)

      expect(response).to have_http_status(:no_content)
      expect(Family::Membership.exists?(membership.id)).to be false
    end

    it 'lets an owner remove a member but prevents removing their own membership' do
      delete "/api/v1/families/members/#{membership.id}", headers: headers(owner)
      expect(response).to have_http_status(:no_content)

      delete '/api/v1/families/membership', headers: headers(owner)
      expect(response).to have_http_status(:unprocessable_content)
      expect(Family::Membership.exists?(ownership.id)).to be true
    end

    it 'rejects a member removing their owner' do
      delete "/api/v1/families/members/#{ownership.id}", headers: headers(member)

      expect(response).to have_http_status(:forbidden)
      expect(Family::Membership.exists?(ownership.id)).to be true
    end

    it 'does not allow deleting a family while other members remain' do
      delete '/api/v1/families/manage', headers: headers(owner)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Family.exists?(family.id)).to be true
    end

    it 'lets an owner delete the family after removing other members' do
      membership.destroy!

      delete '/api/v1/families/manage', headers: headers(owner)

      expect(response).to have_http_status(:no_content)
      expect(Family.exists?(family.id)).to be false
    end

    it 'scopes membership removal to the authenticated family' do
      other_family = create(:family, creator: outsider)
      other_membership = create(:family_membership, family: other_family, user: outsider, role: :owner)

      delete "/api/v1/families/members/#{other_membership.id}", headers: headers(owner)

      expect(response).to have_http_status(:not_found)
      expect(Family::Membership.exists?(other_membership.id)).to be true
    end

    it 'scopes invitation revocation to the authenticated family' do
      other_family = create(:family, creator: outsider)
      invitation = create(:family_invitation, family: other_family, invited_by: outsider)

      delete "/api/v1/families/invitations/#{invitation.token}", headers: headers(owner)

      expect(response).to have_http_status(:not_found)
      expect(invitation.reload).to be_pending
    end
  end

  context 'on a self-hosted instance' do
    include_examples 'family management', true

    it 'allows a self-hosted user to create a family without a subscription' do
      post '/api/v1/families/manage', params: { family: { name: 'Home family' } },
                                    headers: headers(outsider), as: :json

      expect(response).to have_http_status(:created)
      expect(outsider.reload).to be_family_owner
      expect(payload.dig('capacity', 'limit')).to be_nil
    end

    ['', 'a' * 51].each do |name|
      it "returns an explanatory validation error when creating with a #{name.empty? ? 'blank' : 'long'} name" do
        post '/api/v1/families/manage', params: { family: { name: name } },
                                      headers: headers(outsider), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(payload['error']).to eq('validation_failed')
        expect(payload['message']).to be_present
        expect(outsider.reload.family).to be_nil
      end
    end

    it 'allows more than five members' do
      4.times { create(:family_membership, family: family) }
      invitation = create(:family_invitation, family: family, invited_by: owner, email: outsider.email)

      post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)

      expect(response).to have_http_status(:ok)
      expect(family.members.count).to eq(7)
    end
  end

  context 'on Cloud' do
    include_examples 'family management', false

    it 'rejects creating a family without Family access' do
      outsider.update!(plan: :pro, status: :active, active_until: 1.month.from_now)

      post '/api/v1/families/manage', params: { family: { name: 'Unpaid family' } },
                                    headers: headers(outsider), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(outsider.reload.family).to be_nil
    end

    it 'lets a pending-payment invitee join without buying a subscription' do
      outsider.update!(status: :pending_payment, plan: :lite, active_until: nil)
      invitation = create(:family_invitation, family: family, invited_by: owner, email: outsider.email)

      get "/api/v1/families/invitations/#{invitation.token}", headers: headers(outsider)
      expect(response).to have_http_status(:ok)

      post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)
      expect(response).to have_http_status(:ok)
      expect(outsider.reload.family).to eq(family)
    end

    it 'accepts the invitation reserving the fifth and final seat' do
      2.times { create(:family_membership, family: family) }
      invitation = create(:family_invitation, family: family, invited_by: owner, email: outsider.email)
      expect(family.reload).to be_full

      post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)

      expect(response).to have_http_status(:ok)
      expect(family.members.count).to eq(5)
    end

    it 'does not admit a sixth person from a stale invitation' do
      3.times { create(:family_membership, family: family) }
      invitation = create(:family_invitation, family: family, invited_by: owner, email: outsider.email)

      post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)

      expect(response).to have_http_status(:unprocessable_content)
      expect(outsider.reload.family).to be_nil
    end

    context 'after Family access expires' do
      let!(:invitation) { create(:family_invitation, family: family, invited_by: owner, email: outsider.email) }

      before do
        owner.update!(status: :inactive, active_until: 1.day.ago)
        family.update!(access_until: 1.day.ago)
      end

      it 'retains management details and pending invitation visibility' do
        get '/api/v1/families/manage', headers: headers(owner)
        expect(response).to have_http_status(:ok)
        expect(payload.dig('family', 'access_live')).to be false

        get '/api/v1/families/invitations', headers: headers(owner)
        expect(response).to have_http_status(:ok)
        expect(payload['invitations'].pluck('token')).to include(invitation.token)
      end

      it 'blocks invitation sending, renaming and accepting' do
        post '/api/v1/families/invitations', params: { family_invitation: { email: 'new@example.com' } },
                                           headers: headers(owner), as: :json
        expect(response).to have_http_status(:forbidden)

        patch '/api/v1/families/manage', params: { family: { name: 'New name' } },
                                       headers: headers(owner), as: :json
        expect(response).to have_http_status(:forbidden)

        post "/api/v1/families/invitations/#{invitation.token}/accept", headers: headers(outsider)
        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'still permits revoking invitations, removing members and deleting the family' do
        delete "/api/v1/families/invitations/#{invitation.token}", headers: headers(owner)
        expect(response).to have_http_status(:no_content)

        delete "/api/v1/families/members/#{membership.id}", headers: headers(owner)
        expect(response).to have_http_status(:no_content)

        delete '/api/v1/families/manage', headers: headers(owner)
        expect(response).to have_http_status(:no_content)
      end

      it 'still permits a member to leave' do
        member.update!(status: :inactive, active_until: 1.day.ago)
        delete '/api/v1/families/membership', headers: headers(member)

        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
