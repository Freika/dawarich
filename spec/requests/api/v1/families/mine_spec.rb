# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Families::Mine', type: :request do
  let(:user) { create(:user) }
  let(:member) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:owner_membership) { create(:family_membership, user: user, family: family, role: :owner) }
  let!(:member_membership) { create(:family_membership, user: member, family: family, role: :member) }

  describe 'GET /api/v1/families/mine' do
    it 'returns family, me, members and location requests' do
      member.update_family_location_sharing!(true, duration: 'permanent')
      request = create(:family_location_request, requester: member, target_user: user, family: family)

      get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['family']['name']).to eq(family.name)
      expect(json['me']['user_id']).to eq(user.id)
      expect(json['me']['owner']).to be true
      expect(json['me']['sharing']['enabled']).to be false
      expect(json['me']['sharing']['history_window']).to eq('7d')
      member_row = json['members'].find { |m| m['user_id'] == member.id }
      expect(member_row['sharing_enabled']).to be true
      expect(member_row['email_initial']).to eq(member.email.first.upcase)
      expect(json['location_requests']['incoming'].first['id']).to eq(request.id)
      expect(json['location_requests']['incoming'].first['requester']['user_id']).to eq(member.id)
      expect(json['location_requests']['outgoing']).to eq([])
    end

    it 'excludes expired and responded requests' do
      create(:family_location_request, requester: member, target_user: user, family: family,
                                       expires_at: 1.hour.ago)
      create(:family_location_request, requester: member, target_user: user, family: family,
                                       status: :declined)

      get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(JSON.parse(response.body)['location_requests']['incoming']).to eq([])
    end

    it 'returns 404 for a user without a family' do
      solo = create(:user)

      get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{solo.api_key}" }

      expect(response).to have_http_status(:not_found)
    end

    context 'when the Entitlement has lapsed but the Membership survives' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        member.update!(plan: :lite, status: :inactive, active_until: 1.day.ago)
        family.update!(access_until: 1.day.ago)
      end

      it 'answers successfully and says so, rather than refusing' do
        get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{member.api_key}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json['lapsed']).to be true
        expect(json['family']['name']).to eq(family.name)
        expect(json['me']['owner']).to be false
      end

      it 'discloses nothing about the other members' do
        get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{member.api_key}" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json).not_to have_key('members')
        expect(json).not_to have_key('location_requests')
        expect(response.body).not_to include(user.email)
      end

      it 'marks a lapsed Family owner as the owner, so the client can offer renewal' do
        user.update!(plan: :family, status: :inactive, active_until: 1.day.ago)

        get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{user.api_key}" }

        json = JSON.parse(response.body)
        expect(json['lapsed']).to be true
        expect(json['me']['owner']).to be true
      end
    end

    it 'reports an active Family member as not lapsed' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      user.update!(plan: :family, active_until: 1.year.from_now)
      family.update!(access_until: 1.year.from_now)

      get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{member.api_key}" }

      expect(JSON.parse(response.body)['lapsed']).to be false
    end

    it 'still refuses a user who is neither entitled nor in a family' do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      solo = create(:user, plan: :pro)

      get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{solo.api_key}" }

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns 401 without an API key' do
      get '/api/v1/families/mine'

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/families/mine management fields' do
    def get_mine(caller)
      get '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{caller.api_key}" }
      JSON.parse(response.body)
    end

    let!(:invitation) { create(:family_invitation, family: family, invited_by: user, email: 'p@example.com') }

    it 'gives the owner seats, can_invite and the pending invitations' do
      create(:family_invitation, :cancelled, family: family, invited_by: user)
      host! 'family.example.test'

      json = get_mine(user)

      expect(json['seats']).to eq('limit' => nil, 'members' => 2, 'pending' => 1)
      expect(json['can_invite']).to be true
      expect(json['invitations'].map { |i| i['id'] }).to eq([invitation.id])
      row = json['invitations'].first
      expect(row['email']).to eq('p@example.com')
      expect(URI.parse(row['url']).host).to eq('family.example.test')
      expect(row['url']).to end_with("/invitations/#{invitation.token}")
    end

    it 'gives a member seats and can_invite false, and no invitations' do
      json = get_mine(member)

      expect(json['seats']).to be_present
      expect(json['can_invite']).to be false
      expect(json).not_to have_key('invitations')
      expect(response.body).not_to include(invitation.token)
    end

    it 'says inherits_plan false on self-hosted' do
      expect(get_mine(member)['me']['inherits_plan']).to be false
    end

    context 'on cloud' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :family, active_until: 1.year.from_now)
        family.update!(access_until: 1.year.from_now)
      end

      it 'reports the seat limit and whether a seat is free' do
        json = get_mine(user)

        expect(json['seats']).to eq('limit' => Family::MAX_MEMBERS, 'members' => 2, 'pending' => 1)
        expect(json['can_invite']).to be true
      end

      it 'says can_invite false when every seat is taken' do
        2.times { |i| create(:family_invitation, family: family, invited_by: user, email: "f#{i}@example.com") }

        expect(get_mine(user)['can_invite']).to be false
      end

      it 'says inherits_plan true for a member without a subscription of their own' do
        member.update!(subscription_source: :none)

        expect(get_mine(member)['me']['inherits_plan']).to be true
      end

      it 'says inherits_plan false for a member with their own subscription' do
        member.update!(subscription_source: :paddle)

        expect(get_mine(member)['me']['inherits_plan']).to be false
      end

      it 'says inherits_plan false for the owner' do
        expect(get_mine(user)['me']['inherits_plan']).to be false
      end

      context 'when the family has lapsed' do
        before do
          user.update!(plan: :family, active_until: 1.day.ago)
          family.update!(access_until: nil)
        end

        it 'lists the other members and the pending invitations to the owner' do
          json = get_mine(user)

          expect(json['lapsed']).to be true
          expect(json['members']).to eq(
            [{ 'user_id' => member.id, 'email' => member.email,
               'email_initial' => member.email.first.upcase, 'owner' => false }]
          )
          expect(json['invitations'].map { |i| i['id'] }).to eq([invitation.id])
          expect(URI.parse(json['invitations'].first['url']).host).to eq('www.example.com')
        end

        it 'leaves a lapsed member payload unchanged' do
          json = get_mine(member)

          expect(json.keys).to match_array(%w[lapsed family me])
          expect(json['me'].keys).to match_array(%w[user_id owner])
        end
      end
    end
  end

  describe 'POST /api/v1/families/mine' do
    let(:solo) { create(:user) }

    def post_family(caller, body)
      post '/api/v1/families/mine', params: body.to_json,
                                    headers: { 'Authorization' => "Bearer #{caller.api_key}",
                                               'Content-Type' => 'application/json' }
    end

    it 'creates the family with the caller as owner' do
      expect { post_family(solo, { name: 'The Solos' }) }.to change(Family, :count).by(1)

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json['family']['name']).to eq('The Solos')
      expect(json['me']['owner']).to be true
      expect(solo.reload.family_owner?).to be true
    end

    it 'returns already_in_family for a member' do
      post_family(member, { name: 'Another' })

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('already_in_family')
      expect(JSON.parse(response.body)['message']).to be_present
    end

    it 'returns family_already_created for a user who created a family before' do
      create(:family, creator: solo)

      post_family(solo, { name: 'Second' })

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('family_already_created')
    end

    it 'returns invalid_name for an empty body' do
      post_family(solo, {})

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('invalid_name')
      expect(JSON.parse(response.body)['message']).to eq('Family name is required')
    end

    it 'returns invalid_name for a non-string name' do
      post_family(solo, { name: 5 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('invalid_name')
    end

    context 'on cloud' do
      before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

      it 'returns family_plan_required with upgrade_url for a user without the plan' do
        solo.update!(plan: :pro)

        post_family(solo, { name: 'No Plan' })

        expect(response).to have_http_status(:forbidden)
        json = JSON.parse(response.body)
        expect(json['error']).to eq('family_plan_required')
        expect(json).to have_key('upgrade_url')
      end

      it 'returns family_plan_required for a family plan whose period has ended' do
        solo.update!(plan: :family, active_until: 1.day.ago)

        post_family(solo, { name: 'Expired' })

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['error']).to eq('family_plan_required')
      end

      it 'creates the family for a user on an active family plan' do
        solo.update!(plan: :family, active_until: 1.month.from_now)

        post_family(solo, { name: 'Paid' })

        expect(response).to have_http_status(:created)
      end
    end

    it 'returns feature_disabled when the family toggle is off' do
      solo.update!(settings: solo.settings.merge('family_enabled' => false))

      post_family(solo, { name: 'Off' })

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('feature_disabled')
    end
  end

  describe 'PATCH /api/v1/families/mine' do
    def patch_family(caller, body)
      patch '/api/v1/families/mine', params: body.to_json,
                                     headers: { 'Authorization' => "Bearer #{caller.api_key}",
                                                'Content-Type' => 'application/json' }
    end

    it 'renames the family for the owner' do
      patch_family(user, { name: 'Renamed' })

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['family']['name']).to eq('Renamed')
      expect(family.reload.name).to eq('Renamed')
    end

    it 'returns owner_required for a member' do
      patch_family(member, { name: 'Hijack' })

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('owner_required')
      expect(family.reload.name).not_to eq('Hijack')
    end

    it 'returns invalid_name for a blank name' do
      patch_family(user, { name: '  ' })

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('invalid_name')
    end

    it 'returns invalid_name for a 51-character name' do
      patch_family(user, { name: 'a' * 51 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('invalid_name')
    end

    it 'returns 404 for a user without a family' do
      patch_family(create(:user), { name: 'Nope' })

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'DELETE /api/v1/families/mine' do
    def delete_family(caller)
      delete '/api/v1/families/mine', headers: { 'Authorization' => "Bearer #{caller.api_key}" }
    end

    it 'returns family_has_members while another member is present' do
      delete_family(user)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)['error']).to eq('family_has_members')
      expect(Family.exists?(family.id)).to be true
    end

    it 'returns owner_required for a member' do
      delete_family(member)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('owner_required')
    end

    it 'returns 404 for a user without a family' do
      delete_family(create(:user))

      expect(response).to have_http_status(:not_found)
    end

    context 'with a lone owner' do
      before { member_membership.destroy! }

      it 'deletes the family and returns 204' do
        delete_family(user)

        expect(response).to have_http_status(:no_content)
        expect(Family.exists?(family.id)).to be false
      end

      it 'deletes the family for a lapsed cloud owner' do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        user.update!(plan: :family, active_until: 1.day.ago)
        family.update!(access_until: nil)

        delete_family(user)

        expect(response).to have_http_status(:no_content)
        expect(Family.exists?(family.id)).to be false
      end
    end
  end
end
