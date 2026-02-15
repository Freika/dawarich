# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GooglePhotos::Oauth', type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
    allow(DawarichSettings).to receive(:google_photos_available?).and_return(true)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('GOOGLE_OAUTH_CLIENT_ID').and_return('test_client_id')
    allow(ENV).to receive(:[]).with('GOOGLE_OAUTH_CLIENT_SECRET').and_return('test_client_secret')
  end

  describe 'GET /google_photos/oauth/authorize' do
    it 'redirects to Google OAuth' do
      get '/google_photos/oauth/authorize'

      expect(response).to have_http_status(:redirect)
      expect(response.redirect_url).to include('accounts.google.com')
    end

    it 'includes required OAuth parameters' do
      get '/google_photos/oauth/authorize'

      redirect_url = response.redirect_url
      expect(redirect_url).to include('client_id=test_client_id')
      expect(redirect_url).to include('response_type=code')
      expect(redirect_url).to include('access_type=offline')
      expect(redirect_url).to include('photoslibrary.readonly')
    end
  end

  describe 'GET /google_photos/oauth/callback' do
    context 'with error parameter' do
      it 'redirects with error message' do
        get '/google_photos/oauth/callback', params: { error: 'access_denied', error_description: 'User denied access' }

        expect(response).to redirect_to(settings_integrations_path)
        follow_redirect!
        expect(flash[:alert]).to include('User denied access')
      end
    end

    context 'with valid callback' do
      before do
        # Set up the state in session by first making authorize request
        get '/google_photos/oauth/authorize'
        @state = response.redirect_url.match(/state=([^&]+)/)[1]

        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .to_return(
            status: 200,
            body: {
              access_token: 'new_access_token',
              refresh_token: 'new_refresh_token',
              expires_in: 3600
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'exchanges code for tokens' do
        get '/google_photos/oauth/callback', params: { code: 'auth_code', state: @state }

        expect(response).to redirect_to(settings_integrations_path)
        follow_redirect!
        expect(flash[:notice]).to eq('Google Photos connected successfully')
      end

      it 'saves tokens to user settings' do
        get '/google_photos/oauth/callback', params: { code: 'auth_code', state: @state }

        user.reload
        expect(user.settings['google_photos_access_token']).to eq('new_access_token')
        expect(user.settings['google_photos_refresh_token']).to eq('new_refresh_token')
      end
    end

    context 'when token exchange fails' do
      before do
        get '/google_photos/oauth/authorize'
        @state = response.redirect_url.match(/state=([^&]+)/)[1]

        stub_request(:post, 'https://oauth2.googleapis.com/token')
          .to_return(status: 400, body: '{"error": "invalid_grant"}')
      end

      it 'redirects with error' do
        get '/google_photos/oauth/callback', params: { code: 'auth_code', state: @state }

        expect(response).to redirect_to(settings_integrations_path)
        follow_redirect!
        expect(flash[:alert]).to include('Failed to connect')
      end
    end
  end

  describe 'DELETE /google_photos/oauth/disconnect' do
    let(:user) do
      create(:user, settings: {
               'google_photos_access_token' => 'token',
               'google_photos_refresh_token' => 'refresh',
               'google_photos_token_expires_at' => Time.current.to_i
             })
    end

    it 'clears Google Photos tokens' do
      delete '/google_photos/oauth/disconnect'

      user.reload
      expect(user.settings['google_photos_access_token']).to be_nil
      expect(user.settings['google_photos_refresh_token']).to be_nil
      expect(user.settings['google_photos_token_expires_at']).to be_nil
    end

    it 'redirects with success message' do
      delete '/google_photos/oauth/disconnect'

      expect(response).to redirect_to(settings_integrations_path)
      follow_redirect!
      expect(flash[:notice]).to eq('Google Photos disconnected')
    end
  end

  describe 'when Google Photos is not available' do
    before do
      allow(DawarichSettings).to receive(:google_photos_available?).and_return(false)
    end

    it 'redirects authorize with error' do
      get '/google_photos/oauth/authorize'

      expect(response).to redirect_to(settings_integrations_path)
      follow_redirect!
      expect(flash[:alert]).to eq('Google Photos integration is not available')
    end

    it 'redirects callback with error' do
      get '/google_photos/oauth/callback', params: { code: 'auth_code' }

      expect(response).to redirect_to(settings_integrations_path)
      follow_redirect!
      expect(flash[:alert]).to eq('Google Photos integration is not available')
    end

    it 'redirects disconnect with error' do
      delete '/google_photos/oauth/disconnect'

      expect(response).to redirect_to(settings_integrations_path)
      follow_redirect!
      expect(flash[:alert]).to eq('Google Photos integration is not available')
    end
  end
end
