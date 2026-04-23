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

  it 'signs in the user and redirects to the map with a welcome flash' do
    get "/trial/welcome?token=#{token}"
    expect(response).to have_http_status(:found)
    expect(response).to redirect_to(%r{/map/v\d})
    expect(flash[:notice]).to include('Welcome to Dawarich')
    expect(flash[:notice]).to include(user.active_until.strftime('%B %d, %Y'))
  end

  context 'when active_until is not yet populated (Paddle webhook race)' do
    # skip_auto_trial suppresses the `activate` (self-hosted) and
    # `start_trial` (cloud) after_commit hooks so active_until stays nil and
    # we can exercise the race-with-Paddle-webhook path.
    let(:user) do
      create(:user, skip_auto_trial: true, status: :pending_payment, active_until: nil)
    end

    it 'still redirects to the map without raising NoMethodError on nil#strftime' do
      get "/trial/welcome?token=#{token}"

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(%r{/map/v\d})
      expect(flash[:notice]).to include('activated')
    end
  end

  it 'redirects an invalid token to sign-in with a "link invalid or expired" alert' do
    get '/trial/welcome?token=not_a_real_jwt'

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq('Link invalid or expired. Please sign in.')
  end

  it 'redirects an expired token to sign-in with the same alert' do
    expired_token = token # generate before stubbing time so exp is based on real "now"
    allow(Time).to receive(:now).and_return(1.hour.from_now)
    get "/trial/welcome?token=#{expired_token}"

    expect(response).to redirect_to(new_user_session_path)
    expect(flash[:alert]).to eq('Link invalid or expired. Please sign in.')
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
      expect(response).to have_http_status(:found)

      # Simulate the "attacker replays the captured URL from the magic email"
      # after the legitimate user has already visited it.
      delete destroy_user_session_path
      get "/trial/welcome?token=#{t}"
      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'silently redirects to the map when the same signed-in user reloads a consumed link' do
      # Browser back / reload / accidental re-visit of the welcome URL after
      # the user has already been onboarded. For the same signed-in user we
      # just send them to the map without adding a new flash (they already
      # saw the welcome notice on first visit) — and never to /users/sign_in
      # (which would trigger Devise's "You are already signed in" alert).
      Rails.cache.clear
      t = issue_welcome_token(user)
      get "/trial/welcome?token=#{t}"
      expect(response).to redirect_to(%r{/map/v\d})

      # Follow the redirect so the first request's flash gets consumed —
      # otherwise Rack carries it into the next request and masks what the
      # reload branch actually sets.
      follow_redirect! if response.redirect?

      # Same session, same signed-in user — simulate reload.
      get "/trial/welcome?token=#{t}"
      expect(response).to redirect_to(%r{/map/v\d})
      expect(flash[:alert]).to be_blank
      # The reload branch intentionally does NOT set a new flash; the prior
      # redirect's notice has already been consumed above.
      expect(flash[:notice]).to be_blank
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
