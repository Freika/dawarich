# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'settings/general', type: :request do
  context 'when user is authenticated' do
    let!(:user) { create(:user, settings: {}) }

    before do
      sign_in user
    end

    describe 'GET /index' do
      it 'returns a success response' do
        get settings_general_index_url

        expect(response).to be_successful
      end

      it 'renders the timezone dropdown' do
        get settings_general_index_url

        expect(response.body).to include('Your Timezone')
        expect(response.body).to include('select')
      end
    end

    describe 'PATCH /update' do
      context 'with HTML format' do
        it 'updates the timezone and redirects' do
          patch settings_general_path, params: { timezone: 'America/New_York' }

          expect(response).to redirect_to(settings_general_index_path)
          expect(user.reload.settings['timezone']).to eq('America/New_York')
        end

        it 'shows success notice' do
          patch settings_general_path, params: { timezone: 'Europe/London' }

          expect(flash[:notice]).to eq('Timezone updated')
        end
      end

      context 'with JSON format' do
        it 'updates the timezone and returns JSON response' do
          patch settings_general_path, params: { timezone: 'Asia/Tokyo' }, as: :json

          expect(response).to be_successful
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
          expect(json_response['timezone']).to eq('Asia/Tokyo')
          expect(user.reload.settings['timezone']).to eq('Asia/Tokyo')
        end
      end
    end
  end

  context 'when user is not authenticated' do
    it 'redirects to the sign in page' do
      get settings_general_index_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
