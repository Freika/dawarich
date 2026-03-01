# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApplicationController, type: :controller do
  controller do
    before_action :require_pro!

    def index
      render plain: 'ok'
    end
  end

  before do
    routes.draw { get 'index' => 'anonymous#index' }
  end

  describe '#require_pro!' do
    context 'when user is on pro plan' do
      let(:user) { create(:user, plan: :pro) }

      before { sign_in user }

      it 'allows access' do
        get :index

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq('ok')
      end
    end

    context 'when on a self-hosted instance' do
      let(:user) { create(:user) } # default plan is pro

      before { sign_in user }

      it 'allows access regardless of plan' do
        get :index

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when user is on lite plan' do
      let(:user) { create(:user, plan: :lite) }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        sign_in user
      end

      it 'redirects back with alert' do
        get :index

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('This feature requires a Pro plan.')
      end
    end

    context 'when user is not signed in' do
      it 'redirects back with alert' do
        get :index

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to eq('This feature requires a Pro plan.')
      end
    end
  end
end
