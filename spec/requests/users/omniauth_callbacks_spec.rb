# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::OmniauthCallbacks', type: :request do
  let(:email) { 'oauth_user@example.com' }

  before do
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
  end

  shared_examples 'successful OAuth authentication' do |provider, provider_name|
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

    context 'when user already exists' do
      let!(:existing_user) { create(:user, email: email) }

      it 'signs in the existing user without creating a new one' do
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[provider]
          get "/users/auth/#{provider}/callback"
        end.not_to change(User, :count)

        expect(response).to redirect_to(root_path)
      end
    end

    context 'when user creation fails' do
      before do
        allow(User).to receive(:create).and_return(
          User.new(email: email).tap do |u|
            u.errors.add(:email, 'is invalid')
          end
        )
      end

      it 'redirects to registration with error message' do
        Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[provider]
        get "/users/auth/#{provider}/callback"

        expect(response).to redirect_to(new_user_registration_url)
      end
    end
  end

  describe 'GET /users/auth/github/callback' do
    before do
      mock_github_auth(email: email)
    end

    include_examples 'successful OAuth authentication', :github, 'GitHub'
  end

  describe 'GET /users/auth/google_oauth2/callback' do
    before do
      mock_google_auth(email: email)
    end

    include_examples 'successful OAuth authentication', :google_oauth2, 'Google'
  end

  describe 'GET /users/auth/openid_connect/callback' do
    before do
      mock_openid_connect_auth(email: email)
    end

    include_examples 'successful OAuth authentication', :openid_connect, 'OpenID Connect'
  end

  describe 'OAuth flow integration' do
    context 'with GitHub' do
      before { mock_github_auth(email: 'github@example.com') }

      it 'completes the full OAuth flow' do
        # Simulate OAuth callback
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:github]
          get '/users/auth/github/callback'
        end.to change(User, :count).by(1)

        # Verify user is created
        user = User.find_by(email: 'github@example.com')
        expect(user).to be_present
        expect(user.email).to eq('github@example.com')
        expect(response).to redirect_to(root_path)
      end
    end

    context 'with Google' do
      before { mock_google_auth(email: 'google@example.com') }

      it 'completes the full OAuth flow' do
        # Simulate OAuth callback
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:google_oauth2]
          get '/users/auth/google_oauth2/callback'
        end.to change(User, :count).by(1)

        # Verify user is created
        user = User.find_by(email: 'google@example.com')
        expect(user).to be_present
        expect(user.email).to eq('google@example.com')
        expect(response).to redirect_to(root_path)
      end
    end

    context 'with OpenID Connect (Authelia/Authentik)' do
      before { mock_openid_connect_auth(email: 'oidc@example.com') }

      it 'completes the full OAuth flow' do
        # Simulate OAuth callback
        expect do
          Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
          get '/users/auth/openid_connect/callback'
        end.to change(User, :count).by(1)

        # Verify user is created
        user = User.find_by(email: 'oidc@example.com')
        expect(user).to be_present
        expect(user.email).to eq('oidc@example.com')
        expect(response).to redirect_to(root_path)
      end
    end
  end

  describe 'CSRF protection' do
    it 'does not raise CSRF error for GitHub callback' do
      mock_github_auth(email: email)

      expect do
        Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:github]
        get '/users/auth/github/callback'
      end.not_to raise_error
    end

    it 'does not raise CSRF error for Google callback' do
      mock_google_auth(email: email)

      expect do
        Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:google_oauth2]
        get '/users/auth/google_oauth2/callback'
      end.not_to raise_error
    end

    it 'does not raise CSRF error for OpenID Connect callback' do
      mock_openid_connect_auth(email: email)

      expect do
        Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
        get '/users/auth/openid_connect/callback'
      end.not_to raise_error
    end
  end
end
