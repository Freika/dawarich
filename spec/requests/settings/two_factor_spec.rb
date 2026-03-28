# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Settings::TwoFactor', type: :request do
  let(:password) { 'test_password_123' }
  let(:user) { create(:user, password: password) }

  before { sign_in user }

  describe 'GET /settings/two_factor' do
    it 'shows 2FA status page' do
      get settings_two_factor_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'POST /settings/two_factor (enable)' do
    it 'generates OTP secret and shows QR code' do
      expect { post settings_two_factor_path }.to change { user.reload.otp_secret }.from(nil)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Scan QR code')
    end
  end

  describe 'POST /settings/two_factor/verify' do
    before do
      user.update!(otp_secret: User.generate_otp_secret)
    end

    context 'with valid OTP code' do
      it 'enables 2FA and shows backup codes' do
        valid_code = user.current_otp

        post verify_settings_two_factor_path, params: { otp_attempt: valid_code }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('Save your backup codes')
        expect(user.reload.otp_required_for_login).to be true
        expect(user.otp_backup_codes).to be_present
      end
    end

    context 'with invalid OTP code' do
      it 'shows error and re-renders QR code' do
        post verify_settings_two_factor_path, params: { otp_attempt: '000000' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Invalid verification code')
        expect(user.reload.otp_required_for_login).to be false
      end
    end
  end

  describe 'DELETE /settings/two_factor (disable)' do
    before do
      user.update!(
        otp_secret: User.generate_otp_secret,
        otp_required_for_login: true,
        otp_backup_codes: %w[code1 code2]
      )
    end

    context 'with correct password' do
      it 'disables 2FA' do
        delete settings_two_factor_path, params: { password: password }

        expect(response).to redirect_to(settings_two_factor_path)
        user.reload
        expect(user.otp_required_for_login).to be false
        expect(user.otp_secret).to be_nil
        expect(user.otp_backup_codes).to be_nil
      end
    end

    context 'with incorrect password' do
      it 'does not disable 2FA' do
        delete settings_two_factor_path, params: { password: 'wrong_password' }

        expect(response).to redirect_to(settings_two_factor_path)
        expect(flash[:alert]).to eq('Incorrect password.')
        expect(user.reload.otp_required_for_login).to be true
      end
    end
  end
end
