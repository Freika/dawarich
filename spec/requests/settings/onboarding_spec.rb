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
      it 'creates a demo import' do
        expect do
          post demo_data_settings_onboarding_path
        end.to change(Import, :count).by(1)

        expect(response).to redirect_to(root_path)
        expect(Import.last.demo).to be true
      end

      it 'is idempotent' do
        create(:import, user: user, demo: true, name: 'Demo Data (Berlin)')

        expect do
          post demo_data_settings_onboarding_path
        end.not_to change(Import, :count)

        expect(response).to redirect_to(root_path)
      end
    end

    describe 'DELETE /settings/onboarding/demo_data' do
      it 'deletes demo import' do
        demo_import = create(:import, user: user, demo: true, name: 'Demo Data (Berlin)')

        delete demo_data_settings_onboarding_path

        expect(response).to redirect_to(root_path)
        expect(demo_import.reload.status).to eq('deleting')
      end

      it 'handles missing demo import gracefully' do
        delete demo_data_settings_onboarding_path

        expect(response).to redirect_to(root_path)
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
