# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'settings/onboarding', type: :request do
  context 'when user is authenticated' do
    let!(:user) { create(:user) }

    before do
      sign_in user
    end

    describe 'PATCH /settings/onboarding' do
      it 'sets onboarding_completed to true' do
        patch settings_onboarding_path

        expect(response).to have_http_status(:ok)
        expect(user.reload.settings['onboarding_completed']).to be true
      end

      it 'is idempotent' do
        2.times { patch settings_onboarding_path }

        expect(response).to have_http_status(:ok)
        expect(user.reload.settings['onboarding_completed']).to be true
      end
    end
  end

  context 'when user is not authenticated' do
    it 'redirects to the sign in page' do
      patch settings_onboarding_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
