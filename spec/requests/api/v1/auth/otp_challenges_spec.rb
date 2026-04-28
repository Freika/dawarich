# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/otp_challenge', type: :request do
  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  after { Rack::Attack.enabled = false }

  let(:user) do
    u = create(:user, password: 'secret123')
    u.otp_secret = User.generate_otp_secret
    u.otp_required_for_login = true
    u.save!
    u
  end
  let(:challenge_token) { Auth::IssueOtpChallengeToken.new(user).call }

  def current_totp
    ROTP::TOTP.new(user.otp_secret).now
  end

  it 'returns full session on correct TOTP' do
    post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: current_totp }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['api_key']).to eq(user.api_key)
    expect(body['user_id']).to eq(user.id)
  end

  it 'returns 401 on wrong TOTP' do
    post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: '000000' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 on invalid challenge token' do
    post '/api/v1/auth/otp_challenge', params: { challenge_token: 'garbage', otp_code: current_totp }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'accepts a backup code' do
    backup_codes = user.generate_otp_backup_codes!
    user.save!
    post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: backup_codes.first }
    expect(response).to have_http_status(:ok)
  end

  it 'marks the challenge token as consumed so it cannot be replayed' do
    Rails.cache.clear
    post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: current_totp }
    expect(response).to have_http_status(:ok)

    # Replay the same challenge token with a fresh OTP — must be rejected
    post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: current_totp }
    expect(response).to have_http_status(:unauthorized)
    expect(JSON.parse(response.body)['error']).to eq('auth_failed')
  end

  it 'consumes the backup code so it cannot be reused' do
    backup_codes = user.generate_otp_backup_codes!
    user.save!
    code = backup_codes.first
    # First use succeeds
    post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: code }
    expect(response).to have_http_status(:ok)
    # Re-issue token, re-try same backup code
    retry_token = Auth::IssueOtpChallengeToken.new(user).call
    post '/api/v1/auth/otp_challenge', params: { challenge_token: retry_token, otp_code: code }
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'brute-force protection keyed on challenge_token' do
    it 'throttles repeated guesses against the same challenge_token to 5 per window' do
      # 5 wrong attempts should not be throttled; the 6th should
      5.times do
        post '/api/v1/auth/otp_challenge',
             params: { challenge_token: challenge_token, otp_code: '000000' }
        expect(response).to have_http_status(:unauthorized)
      end
      post '/api/v1/auth/otp_challenge',
           params: { challenge_token: challenge_token, otp_code: '000000' }
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'treats distinct challenge_tokens as separate buckets in the token throttle' do
      # Four attempts against token A; defense-in-depth IP throttle (limit 5) is not hit.
      4.times do
        post '/api/v1/auth/otp_challenge',
             params: { challenge_token: challenge_token, otp_code: '000000' }
      end
      # A fifth attempt against a DIFFERENT token passes the token throttle
      # (separate bucket) and is still under the IP throttle — so it reaches
      # the controller and returns 401.
      other_token = Auth::IssueOtpChallengeToken.new(user).call
      post '/api/v1/auth/otp_challenge',
           params: { challenge_token: other_token, otp_code: '000000' }
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
