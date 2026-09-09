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
end
