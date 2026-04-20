# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Two-factor management', type: :request do
  let(:user) { create(:user, password: 'secret123', status: :active) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before { allow(DawarichSettings).to receive(:two_factor_available?).and_return(true) }

  describe 'POST /api/v1/users/me/two_factor/setup' do
    it 'returns provisioning URI and secret' do
      post '/api/v1/users/me/two_factor/setup', headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['provisioning_uri']).to match(%r{^otpauth://totp/})
      expect(body['secret']).to be_present
    end

    it 'does not enable 2FA yet' do
      post '/api/v1/users/me/two_factor/setup', headers: headers
      expect(user.reload.otp_required_for_login).to be false
    end
  end

  describe 'POST /api/v1/users/me/two_factor/confirm' do
    before do
      post '/api/v1/users/me/two_factor/setup', headers: headers
      user.reload
    end

    it 'enables 2FA and returns backup codes on valid OTP' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      post '/api/v1/users/me/two_factor/confirm', params: { otp_code: otp }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['backup_codes']).to be_an(Array)
      expect(body['backup_codes'].length).to eq(10)
      expect(user.reload.otp_required_for_login).to be true
    end

    it 'returns 422 on wrong OTP' do
      post '/api/v1/users/me/two_factor/confirm', params: { otp_code: '000000' }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.otp_required_for_login).to be false
    end
  end

  describe 'POST /api/v1/users/me/two_factor/backup_codes (regenerate)' do
    before do
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.generate_otp_backup_codes!
      user.save!
    end

    it 'requires valid OTP' do
      post '/api/v1/users/me/two_factor/backup_codes',
           params: { otp_code: '000000' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns new codes on valid OTP' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      post '/api/v1/users/me/two_factor/backup_codes',
           params: { otp_code: otp }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['backup_codes'].length).to eq(10)
    end

    it 'accepts the current password instead of OTP' do
      post '/api/v1/users/me/two_factor/backup_codes',
           params: { password: 'secret123' }, headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'DELETE /api/v1/users/me/two_factor' do
    before do
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'disables 2FA with valid OTP' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      delete '/api/v1/users/me/two_factor', params: { otp_code: otp }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(user.reload.otp_required_for_login).to be false
      expect(user.reload.otp_secret).to be_nil
    end

    it 'disables 2FA with valid password' do
      delete '/api/v1/users/me/two_factor', params: { password: 'secret123' }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(user.reload.otp_required_for_login).to be false
    end

    it 'refuses disable without valid credential' do
      delete '/api/v1/users/me/two_factor', params: { otp_code: '000000' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.otp_required_for_login).to be true
    end
  end
end
