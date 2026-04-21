# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /trial/welcome', type: :request do
  let(:user) { create(:user, status: :trial, active_until: 7.days.from_now) }
  let(:token) do
    JWT.encode(
      {
        user_id: user.id,
        purpose: 'trial_welcome',
        jti: SecureRandom.uuid,
        exp: 30.minutes.from_now.to_i
      },
      ENV.fetch('JWT_SECRET_KEY', 'test_secret'),
      'HS256'
    )
  end

  before { Rails.cache.clear }

  it 'signs in the user and renders the welcome page' do
    get "/trial/welcome?token=#{token}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Welcome to Dawarich')
  end

  it 'rejects an invalid token' do
    get '/trial/welcome?token=not_a_real_jwt'
    expect(response).to have_http_status(:unauthorized).or have_http_status(:found) # redirect to sign_in
  end

  it 'rejects an expired token' do
    expired_token = token # generate before stubbing time so exp is based on real "now"
    allow(Time).to receive(:now).and_return(1.hour.from_now)
    get "/trial/welcome?token=#{expired_token}"
    expect(response).to have_http_status(:unauthorized).or have_http_status(:found)
  end

  describe 'security hardening' do
    def issue_welcome_token(user, overrides = {})
      payload = {
        user_id: user.id,
        purpose: 'trial_welcome',
        jti: SecureRandom.uuid,
        exp: 30.minutes.from_now.to_i
      }.merge(overrides)
      JWT.encode(payload, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), 'HS256')
    end

    it 'sends Cache-Control: no-store on the response' do
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response.headers['Cache-Control']).to include('no-store')
    end

    it 'rejects tokens missing purpose=trial_welcome' do
      payload = {
        user_id: user.id,
        jti: SecureRandom.uuid,
        exp: 30.minutes.from_now.to_i
      }
      bad_token = JWT.encode(payload, ENV.fetch('JWT_SECRET_KEY', 'test_secret'), 'HS256')
      get "/trial/welcome?token=#{bad_token}"
      expect(response).to have_http_status(:found)
    end

    it 'consumes the welcome token so it cannot be reused by an attacker' do
      Rails.cache.clear
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response).to have_http_status(:ok)

      # Simulate the "attacker replays the captured URL from the magic email"
      # after the legitimate user has already visited it.
      delete destroy_user_session_path
      get "/trial/welcome?token=#{t}"
      expect(response).to have_http_status(:found)
    end

    it 'refuses auto-signin if a different user is already signed in' do
      other = create(:user, email: 'other@example.com')
      sign_in(other)
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(root_path)
    end
  end
end
