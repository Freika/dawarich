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

  describe 'POST /generate_api_key' do
    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        post '/settings/generate_api_key'

        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before do
        sign_in user
      end

      it 'generates an API key for the user' do
        expect { post '/settings/generate_api_key' }.to(change { user.reload.api_key })
      end

      it 'redirects back' do
        post '/settings/generate_api_key'

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'GET /settings/users' do
    let!(:user) { create(:user, admin: true) }

    before do
      sign_in user
    end

    context 'when self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      end

      it 'returns http success' do
        get '/settings/users'

        expect(response).to have_http_status(:success)
      end
    end

    context 'when not self-hosted' do
      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end

      it 'redirects to root path' do
        get '/settings/users'

        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'PATCH /settings/changelog_consent' do
    context 'when user is not signed in' do
      it 'redirects to the sign in page' do
        patch '/settings/changelog_consent', params: { decision: 'granted' }
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context 'when user is signed in' do
      let(:user) { create(:user) }

      before { sign_in user }

      it 'records granted and responds with a turbo stream replacing the indicator' do
        patch '/settings/changelog_consent', params: { decision: 'granted' },
              headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(response).to have_http_status(:ok)
        expect(user.reload.changelog_consent_granted?).to be(true)
        expect(response.body).to include('version-indicator')
      end

      it 'records declined' do
        patch '/settings/changelog_consent', params: { decision: 'declined' },
              headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(user.reload.changelog_consent_declined?).to be(true)
      end

      it 'lets a user reverse an earlier choice' do
        user.update!(changelog_consent: :granted)

        patch '/settings/changelog_consent', params: { decision: 'declined' },
              headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(user.reload.changelog_consent_declined?).to be(true)
      end

      it 'rejects an invalid decision without changing state' do
        patch '/settings/changelog_consent', params: { decision: 'bogus' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(user.reload.changelog_consent).to be_nil
      end
    end
  end

  describe 'GET /settings/general' do
    let(:user) { create(:user) }

    before { sign_in user }

    it 'renders the opt-in control when notices are off' do
      get settings_general_index_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('changelog-consent-setting')
      expect(response.body).to include('Turn on notices')
    end

    it 'renders the opt-out control once notices are on' do
      user.update!(changelog_consent: :granted)

      get settings_general_index_path

      expect(response.body).to include('Turn off notices')
    end
  end
end
