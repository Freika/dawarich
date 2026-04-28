# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Plan', type: :request do
  describe 'GET /api/v1/plan' do
    context 'when user is on Pro plan' do
      let!(:user) do
        u = create(:user)
        u.update_columns(plan: User.plans[:pro])
        u
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'returns full features' do
        get api_v1_plan_url(api_key: user.api_key)

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['plan']).to eq('pro')
        expect(json['features']['heatmap']).to be(true)
        expect(json['features']['sharing']).to be(true)
        expect(json['features']['data_window']).to be_nil
      end
    end

    context 'when user is on Lite plan' do
      let!(:user) do
        u = create(:user)
        u.update_columns(plan: User.plans[:lite])
        u
      end

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'returns lite features with restrictions' do
        get api_v1_plan_url(api_key: user.api_key)

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['plan']).to eq('lite')
        expect(json['features']['heatmap']).to be(false)
        expect(json['features']['sharing']).to be(false)
        expect(json['features']['write_api']).to eq('create_only')
        expect(json['features']['data_window']).to eq('12_months')
      end
    end

    context 'when on a self-hosted instance' do
      let!(:user) { create(:user) }

      it 'returns full features regardless of plan' do
        get api_v1_plan_url(api_key: user.api_key)

        expect(response).to have_http_status(:ok)

        json = JSON.parse(response.body)
        expect(json['features']['heatmap']).to be(true)
        expect(json['features']['data_window']).to be_nil
      end
    end

    context 'when not authenticated' do
      it 'returns 401' do
        get '/api/v1/plan'

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'subscription metadata' do
      let(:user) { create(:user) }

      it 'includes subscription_source, active_until, and status in the response' do
        user.update!(
          subscription_source: :apple_iap,
          status: :active,
          active_until: 1.year.from_now
        )
        get api_v1_plan_url(api_key: user.api_key)
        body = JSON.parse(response.body)
        expect(body['subscription_source']).to eq('apple_iap')
        expect(body['status']).to eq('active')
        expect(body['active_until']).to be_present
      end
    end
  end
end
