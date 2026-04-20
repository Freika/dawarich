require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/otp_challenge', type: :request do
  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

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
end
