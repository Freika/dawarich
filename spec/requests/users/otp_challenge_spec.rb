# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Sessions OTP Challenge', type: :request do
  let(:password) { 'test_password_123' }
  let(:user) { create(:user, password: password) }

  describe 'login with 2FA enabled' do
    before do
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.generate_otp_backup_codes!
      user.save!
    end

    context 'when password is correct but no OTP provided' do
      it 'shows OTP challenge page' do
        post user_session_path, params: { user: { email: user.email, password: password } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Authentication code')
        expect(session[:otp_user_id]).to eq(user.id)
      end
    end

    context 'when OTP challenge is submitted with valid code' do
      it 'signs in the user' do
        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: user.current_otp }

        expect(response).to redirect_to(root_path)
        expect(session[:otp_user_id]).to be_nil
      end
    end

    context 'when OTP challenge is submitted with invalid code' do
      it 'shows error' do
        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: '000000' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Invalid two-factor code')
      end
    end

    context 'when backup code is used' do
      it 'signs in and invalidates the backup code' do
        backup_code = user.generate_otp_backup_codes!.first
        user.save!

        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: backup_code }

        expect(response).to redirect_to(root_path)
      end
    end

    context 'when OTP session has expired' do
      it 'redirects to login' do
        post user_otp_challenge_path, params: { otp_attempt: '123456' }

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe 'login without 2FA' do
    it 'signs in normally without OTP challenge' do
      post user_session_path, params: { user: { email: user.email, password: password } }

      expect(response).to redirect_to(root_path)
      expect(session[:otp_user_id]).to be_nil
    end
  end

  describe 'login with wrong password' do
    it 'shows login error' do
      post user_session_path, params: { user: { email: user.email, password: 'wrong' } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
