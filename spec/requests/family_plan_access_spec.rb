# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Family plan access gating', type: :request do
  before { allow(DawarichSettings).to receive(:self_hosted?).and_return(false) }

  let(:owner) { create(:user, plan: :family, skip_auto_trial: true) }
  let(:family) { create(:family, creator: owner) }
  let(:member) { create(:user, plan: :lite, skip_auto_trial: true) }

  before do
    create(:family_membership, :owner, family: family, user: owner)
    create(:family_membership, family: family, user: member)
  end

  describe 'write API (require_write_api!)' do
    it 'allows a family owner to recalculate' do
      post "/api/v1/recalculations?api_key=#{owner.api_key}"

      expect(response).to have_http_status(:accepted)
    end

    it 'allows a lite family member to recalculate' do
      post "/api/v1/recalculations?api_key=#{member.api_key}"

      expect(response).to have_http_status(:accepted)
    end

    it 'still blocks a lite user who is not in a family' do
      lone_lite = create(:user, plan: :lite, skip_auto_trial: true)

      post "/api/v1/recalculations?api_key=#{lone_lite.api_key}"

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('write_api_restricted')
    end
  end

  describe 'pro read API (require_pro_api!)' do
    it 'allows a lite family member to access the residency endpoint' do
      get "/api/v1/residency?api_key=#{member.api_key}"

      expect(response).not_to have_http_status(:forbidden)
    end

    it 'blocks a lite user who is not in a family' do
      lone_lite = create(:user, plan: :lite, skip_auto_trial: true)

      get "/api/v1/residency?api_key=#{lone_lite.api_key}"

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)['error']).to eq('pro_plan_required')
    end
  end

  describe 'GET /api/v1/plan' do
    it 'reports full features and family effective plan for a lite family member' do
      get api_v1_plan_url(api_key: member.api_key)

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['plan']).to eq('lite')
      expect(json['effective_plan']).to eq('family')
      expect(json['features']['heatmap']).to be(true)
      expect(json['features']['write_api']).to be(true)
      expect(json['features']['data_window']).to be_nil
    end

    it 'reports full features for the family owner' do
      get api_v1_plan_url(api_key: owner.api_key)

      json = JSON.parse(response.body)
      expect(json['plan']).to eq('family')
      expect(json['effective_plan']).to eq('family')
      expect(json['features']['integrations']).to be(true)
    end
  end

  describe 'map views inject the effective plan for JS layer gating' do
    it 'passes family to Map v2 for a lite family member' do
      sign_in member

      get map_v2_path

      expect(response.body).to include('data-maps--maplibre-user-plan-value="family"')
    end

    it 'passes family to Map v1 for a lite family member' do
      sign_in member

      get map_v1_path

      expect(response.body).to include('data-user_plan="family"')
    end

    it 'still passes lite for a lite user not in a family' do
      lone_lite = create(:user, plan: :lite, skip_auto_trial: true)
      sign_in lone_lite

      get map_v2_path

      expect(response.body).to include('data-maps--maplibre-user-plan-value="lite"')
    end
  end
end
