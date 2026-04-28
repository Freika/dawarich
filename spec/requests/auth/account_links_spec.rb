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
