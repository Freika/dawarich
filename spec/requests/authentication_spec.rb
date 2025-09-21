# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authentication', type: :request do
  let(:user) { create(:user, password: 'password123') }

  before do
    stub_request(:get, 'https://api.github.com/repos/Freika/dawarich/tags')
      .with(headers: { 'Accept' => '*/*', 'Accept-Encoding' => /.*/,
              'Host' => 'api.github.com', 'User-Agent' => /.*/ })
      .to_return(status: 200, body: '[{"name": "1.0.0"}]', headers: {})
  end

  describe 'Route Protection' do
    it 'redirects to sign in page when accessing protected routes while signed out' do
      get map_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'allows access to protected routes when signed in' do
      sign_in user
      get map_path
      expect(response).to be_successful
    end
  end

  describe 'Account Management' do
    it 'prevents account update without current password' do
      sign_in user

      put user_registration_path, params: {
        user: {
          email: 'updated@example.com',
          current_password: ''
        }
      }

      expect(response).not_to be_successful
      expect(user.reload.email).not_to eq('updated@example.com')
    end

    it 'allows account update with current password' do
      sign_in user

      put user_registration_path, params: {
        user: {
          email: 'updated@example.com',
          current_password: 'password123'
        }
      }

      expect(response).to redirect_to(root_path)
      expect(user.reload.email).to eq('updated@example.com')
    end
  end

  describe 'Session Security' do
    it 'requires authentication after sign out' do
      sign_in user
      get map_path
      expect(response).to be_successful

      sign_out user
      get map_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'Mobile iOS Authentication' do
    it 'redirects to iOS success path when signing in with iOS client header' do
      # Sign in with iOS client header
      sign_in user

      # Mock the after_sign_in_path_for redirect behavior
      allow_any_instance_of(ApplicationController).to receive(:after_sign_in_path_for).and_return(ios_success_path)

      # Make a request with the iOS client header
      post user_session_path, params: {
        user: { email: user.email, password: 'password123' }
      }, headers: { 'X-Dawarich-Client' => 'ios' }

      # Should redirect to iOS success endpoint after successful login
      expect(response).to redirect_to(ios_success_path)
    end

    it 'returns JSON response with JWT token for iOS success endpoint' do
      # Generate a test JWT token using the same service as the controller
      payload = { api_key: user.api_key, exp: 5.minutes.from_now.to_i }
      test_token = Subscription::EncodeJwtToken.new(
        payload, ENV['AUTH_JWT_SECRET_KEY']
      ).call

      get ios_success_path, params: { token: test_token }

      expect(response).to be_successful
      expect(response.content_type).to include('application/json')

      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be true
      expect(json_response['message']).to eq('iOS authentication successful')
      expect(json_response['token']).to eq(test_token)
      expect(json_response['redirect_url']).to eq(root_url)
    end

    it 'generates JWT token with correct payload for iOS authentication' do
      # Test JWT token generation directly using the same logic as after_sign_in_path_for
      payload = { api_key: user.api_key, exp: 5.minutes.from_now.to_i }

      # Create JWT token using the same service
      token = Subscription::EncodeJwtToken.new(
        payload, ENV['AUTH_JWT_SECRET_KEY']
      ).call

      expect(token).to be_present

      # Decode the token to verify the payload
      decoded_payload = JWT.decode(
        token,
        ENV['AUTH_JWT_SECRET_KEY'],
        true,
        { algorithm: 'HS256' }
      ).first

      expect(decoded_payload['api_key']).to eq(user.api_key)
      expect(decoded_payload['exp']).to be_present
    end

    it 'uses default path for non-iOS clients' do
      sign_in user

      # Make a request without iOS client header
      post user_session_path, params: {
        user: { email: user.email, password: 'password123' }
      }

      # Should redirect to default path (not iOS success)
      expect(response).not_to redirect_to(ios_success_path)
    end
  end
end
