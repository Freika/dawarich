# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiController, type: :controller do
  controller do
    before_action :require_pro_api!

    def index
      render json: { ok: true }
    end
  end

  before do
    routes.draw { get 'index' => 'anonymous#index' }
  end

  describe '#require_pro_api!' do
    context 'when user is on pro plan' do
      let(:user) { create(:user, plan: :pro) }

      it 'allows access' do
        get :index, params: { api_key: user.api_key }

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq('ok' => true)
      end
    end

    context 'when on a self-hosted instance' do
      let(:user) { create(:user) } # default plan is pro

      it 'allows access regardless of plan' do
        get :index, params: { api_key: user.api_key }

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user is on lite plan' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      let(:user) { create(:user, plan: :lite) }

      it 'returns 403 forbidden with upgrade info' do
        get :index, params: { api_key: user.api_key }

        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body['error']).to eq('pro_plan_required')
        expect(body['upgrade_url']).to be_present
      end
    end

    context 'when user is not authenticated' do
      it 'returns 401 unauthorized' do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
