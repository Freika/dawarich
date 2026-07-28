# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OAuth sign-in with pending import ticket', type: :request do
  let(:email) { 'oauth_user@example.com' }
  let!(:pending_import) { create(:pending_import, :with_file) }

  describe 'Google OAuth callback' do
    before(:all) do
      Rails.application.routes.append do
        devise_scope :user do
          get 'users/auth/google_oauth2/callback', to: 'users/omniauth_callbacks#google_oauth2'
        end
      end
      Rails.application.reload_routes!
    end

    after(:all) do
      Rails.application.reload_routes!
    end

    before do
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      allow(DawarichSettings).to receive(:family_feature_enabled?).and_return(false)
      allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
      allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      stub_const('MANAGER_URL', 'https://manager.example.com')
      Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
      mock_google_auth(email: email)
    end

    def stash_ticket_then_oauth(ticket)
      get new_user_registration_path(import_ticket: ticket)
      expect(session[:pending_import_ticket]).to eq(ticket)

      Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:google_oauth2]
      get '/users/auth/google_oauth2/callback'
    end

    context 'when a new user signs up via Google with a stashed ticket' do
      it 'claims the pending import' do
        expect { stash_ticket_then_oauth(pending_import.claim_ticket) }
          .to change(User, :count).by(1).and change(Import, :count).by(1)

        user = User.find_by(email: email)
        expect(user.imports.count).to eq(1)
        expect(pending_import.reload.claimed_at).to be_present
        expect(pending_import.claimed_by_user_id).to eq(user.id)
        expect(flash[:notice]).to include('Importing')
      end
    end

    context 'when an existing OAuth user signs in via Google with a stashed ticket' do
      let!(:existing_user) do
        create(:user, email: email, provider: 'google_oauth2', uid: '123545')
      end

      it 'claims the pending import for the existing user' do
        expect { stash_ticket_then_oauth(pending_import.claim_ticket) }
          .to change(User, :count).by(0).and change(Import, :count).by(1)

        expect(pending_import.reload.claimed_by_user_id).to eq(existing_user.id)
      end
    end

    context 'when the stashed ticket has expired' do
      let!(:pending_import) { create(:pending_import, :with_file, :expired) }

      it 'does not create an import and warns the user' do
        expect { stash_ticket_then_oauth(pending_import.claim_ticket) }
          .not_to change(Import, :count)

        expect(pending_import.reload.claimed_at).to be_nil
        expect(flash[:alert]).to include('expired or already been used')
      end
    end

    context 'without a stashed ticket' do
      it 'signs in normally without touching pending imports' do
        Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:google_oauth2]

        expect { get '/users/auth/google_oauth2/callback' }.not_to change(Import, :count)

        expect(pending_import.reload.claimed_at).to be_nil
      end
    end
  end

  describe 'Apple OAuth flow' do
    let(:services_id) { 'app.dawarich.web' }
    let(:redirect_uri) { 'https://dawarich.app/users/auth/apple/callback' }
    let(:verifier_double) { instance_double(Auth::VerifyAppleToken) }
    let(:valid_claims) do
      {
        sub: '000777.web.apple',
        email: 'apple-user@example.com',
        email_verified: true,
        is_private_email: false
      }
    end

    before do
      stub_const('APPLE_WEB_SIGN_IN_ENABLED', true)
      stub_const('ENV', ENV.to_hash.merge(
                          'APPLE_WEB_SERVICES_ID' => services_id,
                          'APPLE_WEB_TEAM_ID' => 'H000000B',
                          'APPLE_WEB_KEY_ID' => 'ABC123XYZ',
                          'APPLE_WEB_REDIRECT_URI' => redirect_uri
                        ))
      allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      allow(Auth::VerifyAppleToken).to receive(:new).and_return(verifier_double)
      allow(verifier_double).to receive(:call).and_return(valid_claims)
      https!
    end

    def perform_request_phase
      get '/users/auth/apple'
      location = response.headers['Location']
      Rack::Utils.parse_query(URI(location).query)['state']
    end

    it 'relays the session ticket through the request phase and claims it in the callback' do
      get new_user_registration_path(import_ticket: pending_import.claim_ticket)
      state = perform_request_phase

      expect(cookies['apple_pending_import_ticket']).to be_present

      # Apple's callback is a cross-site form POST: SameSite=Lax means the
      # browser does not send the session cookie. Simulate that by dropping it —
      # the encrypted ticket cookie (SameSite=None) is all the callback gets.
      session_cookie_name = Rails.application.config.session_options[:key] ||
                            cookies.to_hash.keys.find { |k| k.include?('session') }
      cookies.delete(session_cookie_name) if session_cookie_name

      expect do
        post '/users/auth/apple/callback', params: { id_token: 'fake-jwt', state: state }
      end.to change(User, :count).by(1).and change(Import, :count).by(1)

      user = User.find_by(uid: '000777.web.apple')
      expect(pending_import.reload.claimed_by_user_id).to eq(user.id)
      expect(cookies['apple_pending_import_ticket']).to be_blank
    end

    it 'does not set the relay cookie when no ticket is stashed' do
      perform_request_phase

      expect(cookies['apple_pending_import_ticket']).to be_blank
    end
  end
end
