# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::OmniauthCallbacks', type: :request do
  let(:email) { 'oauth_user@example.com' }

  before(:all) do
    # Add OpenID Connect callback route for testing
    # This is needed because OMNIAUTH_PROVIDERS may be empty in test environment
    Rails.application.routes.append do
      devise_scope :user do
        get 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
        post 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
      end
    end
    # Force route recompilation so appended routes are recognized even when
    # prior tests have already triggered route finalization.
    Rails.application.reload_routes!
  end

  after(:all) do
    # Restore original routes
    Rails.application.reload_routes!
  end

  before do
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
  end

  shared_examples 'successful OAuth authentication' do |provider, _provider_name|
    context "when user doesn't exist" do
      it 'creates a new user and signs them in' do
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[provider]
          get "/users/auth/#{provider}/callback"
        end.to change(User, :count).by(1)

        expect(response).to redirect_to(root_path)

        user = User.find_by(email: email)
        expect(user).to be_present
        expect(user.encrypted_password).to be_present
      end
    end

    context 'when an OAuth user with this provider/uid already exists (already linked)' do
      let!(:existing_user) do
        create(:user, email: email, provider: provider.to_s, uid: '123545')
      end

      it 'signs in the existing user without creating a new one' do
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[provider]
          get "/users/auth/#{provider}/callback"
        end.not_to change(User, :count)

        expect(response).to redirect_to(root_path)
      end
    end

    context 'when a local-password account exists with the same email (audit C-1)' do
      let!(:existing_user) { create(:user, email: email, provider: nil, uid: nil) }

      it 'does NOT auto-link and redirects to sign-in with verification message' do
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[provider]
          get "/users/auth/#{provider}/callback"
        end.not_to change(User, :count)

        existing_user.reload
        expect(existing_user.provider).to be_nil
        expect(existing_user.uid).to be_nil

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to include('confirmation link')
      end

      it 'enqueues the OAuth account-link mailer to the existing user' do
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[provider]
          get "/users/auth/#{provider}/callback"
        end.to have_enqueued_job(Users::MailerSendingJob)
          .with(existing_user.id, 'oauth_account_link', hash_including(:provider_label, :link_url))
      end
    end
  end

  # Self-hosted configuration (SELF_HOSTED=true) uses OpenID Connect
  describe 'GET /users/auth/openid_connect/callback' do
    before do
      mock_openid_connect_auth(email: email)
    end

    include_examples 'successful OAuth authentication', :openid_connect, 'OpenID Connect'

    context 'when OIDC auto-registration is disabled' do
      before do
        stub_const('OIDC_AUTO_REGISTER', false)
      end

      context "when user doesn't exist" do
        it 'rejects the user with an appropriate error message' do
          expect do
            Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
            get '/users/auth/openid_connect/callback'
          end.not_to change(User, :count)

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to include('Your account must be created by an administrator')
        end
      end

      context 'when an OIDC-linked user already exists' do
        let!(:existing_user) do
          create(:user, email: email, provider: 'openid_connect', uid: '123545')
        end

        it 'signs in the existing user (already linked by provider+uid)' do
          expect do
            Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
            get '/users/auth/openid_connect/callback'
          end.not_to change(User, :count)

          expect(response).to redirect_to(root_path)
        end
      end

      context 'when a local-password account exists with the same email (audit C-1)' do
        let!(:existing_user) { create(:user, email: email, provider: nil, uid: nil) }

        it 'refuses to auto-link and routes through verification email' do
          expect do
            Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
            get '/users/auth/openid_connect/callback'
          end.not_to change(User, :count)

          existing_user.reload
          expect(existing_user.provider).to be_nil
          expect(existing_user.uid).to be_nil
        end
      end
    end
  end

  describe 'OAuth flow integration with OpenID Connect' do
    context 'with OpenID Connect (Authelia/Authentik/Keycloak)' do
      before { mock_openid_connect_auth(email: 'oidc@example.com') }

      it 'completes the full OAuth flow' do
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
          get '/users/auth/openid_connect/callback'
        end.to change(User, :count).by(1)

        user = User.find_by(email: 'oidc@example.com')
        expect(user).to be_present
        expect(user.email).to eq('oidc@example.com')
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'CSRF protection' do
    it 'does not raise CSRF error for OpenID Connect callback' do
      mock_openid_connect_auth(email: email)

      expect do
        Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
        get '/users/auth/openid_connect/callback'
      end.not_to raise_error
    end
  end

  describe 'pending_payment users' do
    let(:pending_email) { 'pending_oauth@example.com' }
    let!(:pending_user) do
      u = create(:user, email: pending_email, provider: 'openid_connect', uid: '123545',
                        skip_auto_trial: true)
      u.update_columns(status: User.statuses[:pending_payment])
      u
    end

    before { mock_openid_connect_auth(email: pending_email) }

    it 'redirects pending_payment users to /trial/resume after OAuth sign-in' do
      Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
      get '/users/auth/openid_connect/callback'

      expect(response).to redirect_to(trial_resume_path)
    end
  end
end
