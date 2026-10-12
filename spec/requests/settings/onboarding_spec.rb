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

    describe 'POST /settings/onboarding/demo_data' do
      it 'creates demo data and redirects to map v2' do
        post demo_data_settings_onboarding_path

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('/map/v2', 'panel=timeline', 'date=')
      end

      it 'is idempotent and redirects to map v2' do
        post demo_data_settings_onboarding_path
        post demo_data_settings_onboarding_path

        expect(response).to have_http_status(:redirect)
        expect(response.location).to include('/map/v2', 'panel=timeline', 'date=')
      end

      context 'when user is on a non-UTC timezone' do
        let!(:user) { create(:user, settings: { 'timezone' => 'Europe/Berlin' }) }

        it 'uses the user timezone for start_at and end_at, not the Rails default' do
          post demo_data_settings_onboarding_path

          expect(response).to have_http_status(:redirect)
          expect(response.location).to match(/start_at=[^&]*(%2B02%3A00|%2B01%3A00)/)
          expect(response.location).to match(/end_at=[^&]*(%2B02%3A00|%2B01%3A00)/)
        end
      end
    end

    describe 'DELETE /settings/onboarding/demo_data' do
      it 'destroys demo data synchronously and redirects to root' do
        post demo_data_settings_onboarding_path

        delete demo_data_settings_onboarding_path

        expect(response).to redirect_to(root_path)
      end

      it 'handles missing demo data gracefully' do
        delete demo_data_settings_onboarding_path

        expect(response).to redirect_to(root_path)
      end

      it 'redirects to root with alert when destroy raises' do
        post demo_data_settings_onboarding_path
        allow_any_instance_of(Import).to receive(:destroy).and_raise(StandardError, 'boom')

        delete demo_data_settings_onboarding_path

        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
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
