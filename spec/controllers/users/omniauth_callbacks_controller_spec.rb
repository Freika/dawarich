# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Users::OmniauthCallbacksController, type: :controller do
  before do
    @request.env['devise.mapping'] = Devise.mappings[:user]
  end

  describe 'GET #google_oauth2' do
    let(:auth_hash) do
      {
        'provider' => 'google_oauth2',
        'uid' => '123456789',
        'info' => {
          'email' => 'test@example.com',
          'name' => 'Test User',
          'image' => 'https://example.com/avatar.jpg'
        }
      }
    end

    before do
      @request.env['omniauth.auth'] = auth_hash
    end

    context 'when user is successfully created' do
      it 'signs in the user and redirects' do
        get :google_oauth2
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to include('Successfully authenticated from Google')
      end
    end

    context 'when user creation fails' do
      before do
        allow(User).to receive(:from_omniauth).and_return(
          double('user', persisted?: false, errors: double('errors', full_messages: ['Error message']))
        )
      end

      it 'stores auth data in session and redirects to registration' do
        get :google_oauth2
        expect(session['devise.oauth_data']).to be_present
        expect(response).to redirect_to(new_user_registration_path)
        expect(flash[:alert]).to include('Error message')
      end
    end
  end

  describe 'GET #github' do
    let(:auth_hash) do
      {
        'provider' => 'github',
        'uid' => '987654321',
        'info' => {
          'email' => 'github@example.com',
          'name' => 'GitHub User'
        }
      }
    end

    before do
      @request.env['omniauth.auth'] = auth_hash
    end

    it 'handles GitHub authentication' do
      get :github
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'GET #microsoft_office365' do
    let(:auth_hash) do
      {
        'provider' => 'microsoft_office365',
        'uid' => '555666777',
        'info' => {
          'email' => 'microsoft@example.com',
          'name' => 'Microsoft User'
        }
      }
    end

    before do
      @request.env['omniauth.auth'] = auth_hash
    end

    it 'handles Microsoft authentication' do
      get :microsoft_office365
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'GET #openid_connect' do
    context 'with Authentik provider' do
      let(:auth_hash) do
        {
          'provider' => 'authentik',
          'uid' => 'auth123',
          'info' => {
            'email' => 'authentik@example.com',
            'name' => 'Authentik User'
          }
        }
      end

      before do
        @request.env['omniauth.auth'] = auth_hash
      end

      it 'handles Authentik authentication' do
        get :openid_connect
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to include('Successfully authenticated from Authentik')
      end
    end

    context 'with Authelia provider' do
      let(:auth_hash) do
        {
          'provider' => 'authelia',
          'uid' => 'auth456',
          'info' => {
            'email' => 'authelia@example.com',
            'name' => 'Authelia User'
          }
        }
      end

      before do
        @request.env['omniauth.auth'] = auth_hash
      end

      it 'handles Authelia authentication' do
        get :openid_connect
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to include('Successfully authenticated from Authelia')
      end
    end

    context 'with Keycloak provider' do
      let(:auth_hash) do
        {
          'provider' => 'keycloak',
          'uid' => 'auth789',
          'info' => {
            'email' => 'keycloak@example.com',
            'name' => 'Keycloak User'
          }
        }
      end

      before do
        @request.env['omniauth.auth'] = auth_hash
      end

      it 'handles Keycloak authentication' do
        get :openid_connect
        expect(response).to have_http_status(:redirect)
        expect(flash[:notice]).to include('Successfully authenticated from Keycloak')
      end
    end
  end

  describe 'GET #failure' do
    it 'redirects to root with error message' do
      get :failure
      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq('Authentication failed, please try again.')
    end
  end
end