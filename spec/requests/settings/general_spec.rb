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
    end

    describe 'PATCH /update' do
      it 'updates email settings with checkbox value' do
        patch settings_general_path, params: { digest_emails_enabled: '0' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['digest_emails_enabled']).to eq(false)
      end

      it 'enables email settings' do
        patch settings_general_path, params: { digest_emails_enabled: '1' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['digest_emails_enabled']).to eq(true)
      end

      it 'disables news emails setting' do
        patch settings_general_path, params: { news_emails_enabled: '0' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['news_emails_enabled']).to eq(false)
      end

      it 'enables news emails setting' do
        patch settings_general_path, params: { news_emails_enabled: '1' }

        expect(response).to redirect_to(settings_general_index_path)
        expect(user.reload.settings['news_emails_enabled']).to eq(true)
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
