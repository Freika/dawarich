# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings', type: :request do
  describe 'GET /theme' do
    let(:params) { { theme: 'light' } }

    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        get '/settings/theme', params: params
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it 'updates the user theme' do
        get '/settings/theme', params: params
        expect(user.reload.theme).to eq('light')
      end

      it 'redirects to the root path' do
        get '/settings/theme', params: params
        expect(response).to redirect_to(root_path)
      end

      context 'when theme is dark' do
        let(:params) { { theme: 'dark' } }

        it 'updates the user theme' do
          get '/settings/theme', params: params
          expect(user.reload.theme).to eq('dark')
        end
      end
    end
  end
end
