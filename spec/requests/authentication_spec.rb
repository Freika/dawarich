# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Authentication', type: :request do
  let(:user) { create(:user, password: 'password123') }

  before do
    stub_request(:get, "https://api.github.com/repos/Freika/dawarich/tags")
      .with(headers: { 'Accept'=>'*/*', 'Accept-Encoding'=>/.*/,
              'Host'=>'api.github.com', 'User-Agent'=>/.*/})
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
end
