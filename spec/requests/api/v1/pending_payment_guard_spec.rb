# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1 pending_payment guard', type: :request do
  before do
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  describe 'pending_payment user hitting a guarded endpoint' do
    let!(:user) do
      u = create(:user, skip_auto_trial: true)
      u.update_columns(status: User.statuses[:pending_payment], plan: User.plans[:lite])
      u.reload
    end

    it 'returns 402 with payment_required error on /api/v1/points' do
      get api_v1_points_url(api_key: user.api_key)

      expect(response).to have_http_status(:payment_required)

      json = JSON.parse(response.body)
      expect(json['error']).to eq('payment_required')
      expect(json['message']).to be_present
      expect(json['resume_url']).to be_present
    end
  end

  describe 'pending_payment user hitting /api/v1/plan (skipped guard)' do
    let!(:user) do
      u = create(:user, skip_auto_trial: true)
      u.update_columns(status: User.statuses[:pending_payment], plan: User.plans[:lite])
      u.reload
    end

    it 'returns 200 so the client can render the resume-signup UI' do
      get api_v1_plan_url(api_key: user.api_key)

      expect(response).to have_http_status(:ok)

      json = JSON.parse(response.body)
      expect(json['status']).to eq('pending_payment')
    end
  end

  describe 'active user hitting a guarded endpoint' do
    let!(:user) { create(:user, status: :active) }

    it 'is not blocked with 402' do
      get api_v1_points_url(api_key: user.api_key)

      expect(response).not_to have_http_status(:payment_required)
    end
  end
end
