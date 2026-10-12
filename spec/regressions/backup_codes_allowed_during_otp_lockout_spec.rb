# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Backup codes allowed during OTP lockout', type: :request do
  let(:password) { 'test_password_123' }
  let(:user) { create(:user, password: password) }
  let(:backup_code) do
    code = user.generate_otp_backup_codes!.first
    user.save!
    code
  end

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    user.otp_secret = User.generate_otp_secret
    user.otp_required_for_login = true
    user.save!
    backup_code
    user.update_columns(otp_locked_at: 1.minute.ago)
  end

  describe 'web sign-in flow' do
    it 'signs in when a valid backup code is supplied during lockout' do
      post user_session_path, params: { user: { email: user.email, password: password } }
      post user_otp_challenge_path, params: { otp_attempt: backup_code }

      expect(response).to redirect_to(root_path)
      expect(user.reload.failed_otp_attempts).to eq(0)
      expect(user.otp_locked_at).to be_nil
    end

    it 'still blocks TOTP codes during lockout' do
      post user_session_path, params: { user: { email: user.email, password: password } }
      post user_otp_challenge_path, params: { otp_attempt: user.current_otp }

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to include('locked')
    end
  end

  describe 'mobile API flow' do
    let(:challenge_token) { Auth::IssueOtpChallengeToken.new(user).call }

    it 'returns 200 when a valid backup code is supplied during lockout' do
      post '/api/v1/auth/otp_challenge',
           params: { challenge_token: challenge_token, otp_code: backup_code },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.failed_otp_attempts).to eq(0)
      expect(user.otp_locked_at).to be_nil
    end

    it 'returns 423 when a TOTP code is supplied during lockout' do
      post '/api/v1/auth/otp_challenge',
           params: { challenge_token: challenge_token, otp_code: user.current_otp },
           as: :json

      expect(response).to have_http_status(:locked)
    end
  end
end
