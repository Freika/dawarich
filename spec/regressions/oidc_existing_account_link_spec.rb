# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'OIDC existing-account linking', type: :request do
  let(:email) { 'existing@example.com' }

  before(:all) do
    Rails.application.routes.append do
      devise_scope :user do
        get 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
      end
    end
    Rails.application.reload_routes!
  end

  after(:all) do
    Rails.application.reload_routes!
  end

  before do
    stub_const('OIDC_AUTO_REGISTER', false)
    create(:user, email: email, provider: nil, uid: nil)
    mock_openid_connect_auth(email: email)
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
    Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
  end

  it 'offers the linking challenge without creating or linking an account' do
    expect { get '/users/auth/openid_connect/callback' }.not_to change(User, :count)

    user = User.find_by!(email: email)
    expect(user.provider).to be_nil
    expect(user.uid).to be_nil
    expect(response).to redirect_to(auth_account_link_challenge_path)
  end
end
