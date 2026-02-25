# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users', type: :request do
  describe 'GET /users/sign_up' do
    context 'when self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      it 'redirects to root path' do
        get '/users/sign_up'
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include('Registration is not available')
      end
    end

    context 'when not self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'returns http success' do
        get '/users/sign_up'
        expect(response).to have_http_status(:success)
      end
    end
  end
end
