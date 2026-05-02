# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Two-factor management', type: :request do
  let(:user) { create(:user, password: 'secret123456', status: :active) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  describe 'POST /api/v1/users/me/two_factor/setup' do
    it 'returns provisioning URI and secret with valid password' do
      post '/api/v1/users/me/two_factor/setup', params: { password: 'secret123456' }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['provisioning_uri']).to match(%r{^otpauth://totp/})
      expect(body['secret']).to be_present
    end

    it 'rotates the secret on each call (until 2FA is confirmed)' do
      post '/api/v1/users/me/two_factor/setup', params: { password: 'secret123456' }, headers: headers
      first_secret = JSON.parse(response.body)['secret']

      post '/api/v1/users/me/two_factor/setup', params: { password: 'secret123456' }, headers: headers
      second_secret = JSON.parse(response.body)['secret']

      expect(second_secret).not_to eq(first_secret)
    end

    it 'returns 401 without a password' do
      post '/api/v1/users/me/two_factor/setup', headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.otp_secret).to be_nil
    end

    it 'returns 401 with the wrong password' do
      post '/api/v1/users/me/two_factor/setup', params: { password: 'wrong' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.otp_secret).to be_nil
    end

    it 'does not enable 2FA yet' do
      post '/api/v1/users/me/two_factor/setup', params: { password: 'secret123456' }, headers: headers
      expect(user.reload.otp_required_for_login).to be false
    end

    context 'when 2FA is already enabled' do
      before do
        user.otp_secret = User.generate_otp_secret
        user.otp_required_for_login = true
        user.save!
      end

      it 'returns 409 conflict and does not rotate the secret' do
        original_secret = user.otp_secret
        post '/api/v1/users/me/two_factor/setup', params: { password: 'secret123456' }, headers: headers
        expect(response).to have_http_status(:conflict)
        expect(user.reload.otp_secret).to eq(original_secret)
      end
    end
  end

  describe 'POST /api/v1/users/me/two_factor/confirm' do
    before do
      post '/api/v1/users/me/two_factor/setup', params: { password: 'secret123456' }, headers: headers
      user.reload
    end

    it 'enables 2FA and returns backup codes on valid OTP plus password re-auth' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      post '/api/v1/users/me/two_factor/confirm',
           params: { otp_code: otp, password: 'secret123456' }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['backup_codes']).to be_an(Array)
      expect(body['backup_codes'].length).to eq(10)
      expect(user.reload.otp_required_for_login).to be true
    end

    it 'returns 422 on wrong OTP even with valid password' do
      post '/api/v1/users/me/two_factor/confirm',
           params: { otp_code: '000000', password: 'secret123456' }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.otp_required_for_login).to be false
    end

    it 'returns 401 when no password is provided (credential gate)' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      post '/api/v1/users/me/two_factor/confirm', params: { otp_code: otp }, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.otp_required_for_login).to be false
    end

    it 'returns 401 when the password is wrong' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      post '/api/v1/users/me/two_factor/confirm',
           params: { otp_code: otp, password: 'not-the-password' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
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

    it 'returns new codes with valid password' do
      post '/api/v1/users/me/two_factor/backup_codes',
           params: { password: 'secret123456' }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['backup_codes'].length).to eq(10)
    end

    it 'returns 401 without password (OTP alone is no longer accepted)' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      post '/api/v1/users/me/two_factor/backup_codes',
           params: { otp_code: otp }, headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 401 with wrong password' do
      post '/api/v1/users/me/two_factor/backup_codes',
           params: { password: 'wrong' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/users/me/two_factor' do
    before do
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    # audit M-1: disabling 2FA must require BOTH password and a valid OTP /
    # backup code. The previous gate accepted either factor alone, so a
    # leaked password (or a stolen API session) was enough to strip 2FA.
    it 'disables 2FA with valid password AND valid OTP' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      delete '/api/v1/users/me/two_factor',
             params: { password: 'secret123456', otp_code: otp }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(user.reload.otp_required_for_login).to be false
      expect(user.reload.otp_secret).to be_nil
    end

    it 'disables 2FA with valid password AND valid backup code' do
      backup = user.generate_otp_backup_codes!.first
      user.save!

      delete '/api/v1/users/me/two_factor',
             params: { password: 'secret123456', otp_code: backup }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(user.reload.otp_required_for_login).to be false
    end

    it 'refuses to disable with password alone (no OTP)' do
      delete '/api/v1/users/me/two_factor', params: { password: 'secret123456' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.otp_required_for_login).to be true
    end

    it 'refuses to disable with OTP alone (no password)' do
      otp = ROTP::TOTP.new(user.otp_secret).now
      delete '/api/v1/users/me/two_factor', params: { otp_code: otp }, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.otp_required_for_login).to be true
    end

    it 'refuses to disable with valid password but invalid OTP' do
      delete '/api/v1/users/me/two_factor',
             params: { password: 'secret123456', otp_code: '000000' }, headers: headers
      expect(response).to have_http_status(:unauthorized)
      expect(user.reload.otp_required_for_login).to be true
    end

    describe 'brute-force protection' do
      before do
        Rack::Attack.enabled = true
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
      end
      after { Rack::Attack.enabled = false }

      it 'throttles repeated disable attempts keyed on the Authorization header' do
        5.times do
          delete '/api/v1/users/me/two_factor',
                 params: { password: 'secret123456', otp_code: '000000' }, headers: headers
        end
        delete '/api/v1/users/me/two_factor',
               params: { password: 'secret123456', otp_code: '000000' }, headers: headers
        expect(response).to have_http_status(:too_many_requests)
      end
    end
  end
end
