# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /auth/account_link', type: :request do
  let(:user) { create(:user, email: 'user@example.com') }

  def issue(provider: 'apple', uid: 'apple-sub-42', subject: user)
    Auth::IssueAccountLinkToken.new(subject, provider: provider, uid: uid).call
  end

  before { Rails.cache.clear }

  it 'links the identity and signs the user in when 2FA is NOT required' do
    token = issue
    get "/auth/account_link?token=#{token}"

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to match(/Sign in with Apple is now linked/)
    user.reload
    expect(user.provider).to eq('apple')
    expect(user.uid).to eq('apple-sub-42')
  end

  context 'when the user has 2FA enabled' do
    before do
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'links the identity but does NOT sign the user in (no 2FA bypass)' do
      token = issue
      get "/auth/account_link?token=#{token}"

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to match(/linked.*Sign in.*2FA/mi)
      user.reload
      expect(user.provider).to eq('apple')
      expect(user.uid).to eq('apple-sub-42')
    end
  end

  it 'rejects a token whose jti has already been atomically consumed' do
    token = issue
    decoded = JWT.decode(token, ENV.fetch('JWT_SECRET_KEY'), false).first
    Auth::VerifyAccountLinkToken.consume!(decoded['jti'])

    get "/auth/account_link?token=#{token}"

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to match(/already been used/i)
    expect(user.reload.provider).to be_nil
  end

  it 'sends Cache-Control: no-store' do
    token = issue
    get "/auth/account_link?token=#{token}"

    expect(response.headers['Cache-Control']).to include('no-store')
  end

  it 'rejects a replayed link with an "already used" alert' do
    token = issue
    get "/auth/account_link?token=#{token}" # first use, succeeds

    # Replay — sign out to simulate an attacker on a different session
    delete destroy_user_session_path
    get "/auth/account_link?token=#{token}"

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to match(/already been used/i)
  end

  it 'rejects an invalid token' do
    get '/auth/account_link?token=not.a.real.jwt'

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to match(/invalid or expired/i)
  end

  context 'when the user is already linked to a different oauth identity' do
    before { user.update!(provider: 'google', uid: 'google-existing') }

    it 'refuses to overwrite and redirects to sign-in with an explanatory alert' do
      token = issue(provider: 'apple', uid: 'apple-sub-42')
      get "/auth/account_link?token=#{token}"

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to match(/already linked to a different google/i)
      user.reload
      expect(user.provider).to eq('google')
      expect(user.uid).to eq('google-existing')
    end

    it 'does NOT consume the token when refusing the overwrite' do
      token = issue(provider: 'apple', uid: 'apple-sub-42')
      get "/auth/account_link?token=#{token}" # rejected, token NOT consumed

      user.update!(provider: nil, uid: nil)
      get "/auth/account_link?token=#{token}"
      expect(user.reload.provider).to eq('apple')
    end
  end
end

RSpec.describe 'OAuth account-link password challenge', type: :request do
  let(:password) { 'secret-password-123' }
  let(:email) { 'oauth_user@example.com' }
  let!(:user) { create(:user, email: email, password: password, provider: nil, uid: nil) }

  before(:all) do
    Rails.application.routes.append do
      devise_scope :user do
        get 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
      end
    end
    Rails.application.reload_routes!
  end

  before do
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:openid_connect] = OmniAuth::AuthHash.new(
      provider: 'openid_connect',
      uid: '123545',
      info: { email: email, name: 'Test' },
      extra: { raw_info: { email_verified: true } }
    )
    Rails.application.env_config['omniauth.auth'] = OmniAuth.config.mock_auth[:openid_connect]
    Rails.cache.clear
  end

  after do
    OmniAuth.config.mock_auth[:openid_connect] = nil
    Rails.application.env_config.delete('omniauth.auth')
  end

  def trigger_collision
    get '/users/auth/openid_connect/callback'
    expect(response).to redirect_to(auth_account_link_challenge_path)
  end

  describe 'GET /auth/account_link/challenge' do
    it 'renders the password form after an OAuth email collision' do
      trigger_collision
      get auth_account_link_challenge_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(email)
    end

    it 'redirects to sign-in when no pending link in session' do
      get auth_account_link_challenge_path
      expect(response).to redirect_to(new_user_session_path)
    end
  end

  describe 'POST /auth/account_link/challenge' do
    it 'links the identity and signs in when password is correct' do
      trigger_collision
      post confirm_auth_account_link_path, params: { password: password }

      expect(response).to redirect_to(root_path)
      user.reload
      expect(user.provider).to eq('openid_connect')
      expect(user.uid).to eq('123545')
    end

    it 'rejects an incorrect password without linking' do
      trigger_collision
      post confirm_auth_account_link_path, params: { password: 'wrong-password' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('Incorrect password')
      user.reload
      expect(user.provider).to be_nil
      expect(user.uid).to be_nil
    end

    it 'redirects to sign-in (without linking) when no pending link' do
      post confirm_auth_account_link_path, params: { password: password }

      expect(response).to redirect_to(new_user_session_path)
      expect(user.reload.provider).to be_nil
    end

    context 'when the user has 2FA enabled' do
      before do
        user.otp_secret = User.generate_otp_secret
        user.otp_required_for_login = true
        user.save!
      end

      it 'links but does NOT sign the user in (no 2FA bypass)' do
        trigger_collision
        post confirm_auth_account_link_path, params: { password: password }

        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:notice]).to match(/2FA/)
        expect(user.reload.provider).to eq('openid_connect')
      end
    end
  end

  describe 'POST /auth/account_link/email' do
    it 'enqueues the OAuth link mailer when a pending link is present' do
      trigger_collision
      expect do
        post email_fallback_auth_account_link_path
      end.to have_enqueued_job(Users::MailerSendingJob)
        .with(user.id, 'oauth_account_link', hash_including(:provider_label, :link_url))

      expect(response).to redirect_to(new_user_session_path)
    end

    it 'does not re-send within the rate-limit window' do
      trigger_collision
      post email_fallback_auth_account_link_path

      expect do
        post email_fallback_auth_account_link_path
      end.not_to have_enqueued_job(Users::MailerSendingJob)
    end
  end
end
