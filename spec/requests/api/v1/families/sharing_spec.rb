# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Families::Sharing', type: :request do
  let(:user) { create(:user) }
  let(:family) { create(:family, creator: user) }
  let!(:membership) { create(:family_membership, user: user, family: family, role: :owner) }

  describe 'PATCH /api/v1/families/sharing' do
    it 'enables sharing with duration and history settings' do
      patch '/api/v1/families/sharing',
            params: { enabled: true, duration: '24h', share_history: true, history_window: '30d' },
            headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['enabled']).to be true
      expect(json['expires_at']).to be_present
      expect(user.reload.family_sharing_enabled?).to be true
      expect(user.family_share_history?).to be true
      expect(user.family_history_window).to eq('30d')
    end

    it 'disables sharing' do
      user.update_family_location_sharing!(true, duration: 'permanent')

      patch '/api/v1/families/sharing',
            params: { enabled: false },
            headers: { 'Authorization' => "Bearer #{user.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(user.reload.family_sharing_enabled?).to be false
    end

    it 'allows a lite-plan family member to update sharing' do
      lite_member = create(:user)
      create(:family_membership, user: lite_member, family: family, role: :member)
      lite_member.update!(plan: :lite) if lite_member.respond_to?(:plan)

      patch '/api/v1/families/sharing',
            params: { enabled: true, duration: 'permanent' },
            headers: { 'Authorization' => "Bearer #{lite_member.api_key}" }

      expect(response).to have_http_status(:ok)
      expect(lite_member.reload.family_sharing_enabled?).to be true
    end

    it 'returns 404 for a user without a family' do
      solo = create(:user)

      patch '/api/v1/families/sharing',
            params: { enabled: true },
            headers: { 'Authorization' => "Bearer #{solo.api_key}" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
