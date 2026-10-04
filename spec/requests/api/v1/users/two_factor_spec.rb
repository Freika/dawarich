# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Two-factor management', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user, password: 'secret123456', status: :active) }
  let(:headers) { { 'Authorization' => "Bearer #{user.api_key}" } }

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  describe 'A4 OTP API contract' do
    let(:instant) { Time.utc(2026, 10, 3, 12) }
    let(:secret) { 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }

    it 'API availability follows auth and payment but precedes password' do
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(false)
      actions = [[:post, '/setup'], [:post, '/confirm'], [:post, '/backup_codes'], [:delete, '']]
      actions.each do |method, suffix|
        path = "/api/v1/users/me/two_factor#{suffix}"
        public_send(method, path)
        expect(response).to have_http_status(:unauthorized)
        user.update!(status: :pending_payment)
        public_send(method, path, headers: headers)
        expect(response).to have_http_status(:payment_required)
        expect(JSON.parse(response.body)['error']).to eq('payment_required')
        user.update!(status: :inactive)
        before = user.reload.attributes
        public_send(method, path, headers: headers)
        expect(response).to have_http_status(:service_unavailable)
        expect(JSON.parse(response.body)).to eq('error' => 'two_factor_not_available')
        expect(user.reload.attributes).to eq(before)
      end
    end

    it 'API confirm uses one-second drift without consuming or resetting counters' do
      user.update!(otp_secret: secret, consumed_timestep: instant.to_i / 30,
                   failed_otp_attempts: 3, otp_locked_at: instant - 60)
      totp = ROTP::TOTP.new(secret)
      vectors = [[0, -30, 200], [1, -30, 422], [28, 30, 422], [29, 30, 200],
                 [0, 0, 200], [0, 0, 200]]
      vectors.each do |offset, code_offset, status|
        previous = user.reload.attributes
        travel_to(instant + offset) do
          post '/api/v1/users/me/two_factor/confirm',
               params: { password: 'secret123456', otp_code: totp.at(instant + code_offset) }, headers: headers
          expect(response.status).to eq(status)
          user.reload
          expect(user.attributes.except('otp_required_for_login', 'otp_backup_codes', 'updated_at')).to eq(
            previous.except('otp_required_for_login', 'otp_backup_codes', 'updated_at')
          )
          if status == 200
            expect(JSON.parse(response.body)['backup_codes'].length).to eq(10)
            expect(user.otp_backup_codes).not_to eq(previous['otp_backup_codes'])
          else
            expect(JSON.parse(response.body)).to eq('error' => 'invalid_otp')
            expect(user.attributes).to eq(previous)
          end
        end
      end
      current = totp.at(instant)
      [" #{current} ", current[0, 5], "0#{current}"].each do |code|
        travel_to(instant) do
          post '/api/v1/users/me/two_factor/confirm',
               params: { password: 'secret123456', otp_code: code }, headers: headers
          expect(response).to have_http_status(:unprocessable_content)
        end
      end
    end

    it 'API backup regeneration is legal while disabled and preserves flag and secret' do
      [nil, secret].each do |otp_secret|
        user.update!(otp_secret: otp_secret, otp_required_for_login: false)
        old_code = user.generate_otp_backup_codes!.first
        user.save!
        before = user.reload.attributes
        travel_to(instant) do
          post '/api/v1/users/me/two_factor/backup_codes', params: { password: 'secret123456' }, headers: headers
        end
        expect(response).to have_http_status(:ok)
        codes = JSON.parse(response.body)['backup_codes']
        expect(codes.length).to eq(10)
        expect(codes.uniq.length).to eq(10)
        expect(user.reload.attributes.except('otp_backup_codes', 'updated_at')).to eq(
          before.except('otp_backup_codes', 'updated_at')
        )
        expect(user.otp_backup_codes).not_to eq(before['otp_backup_codes'])
        expect(user.invalidate_otp_backup_code!(old_code)).to be(false)
        expect(user.invalidate_otp_backup_code!(codes.first)).to be(true)
        expect(user.invalidate_otp_backup_code!(codes.first)).to be(false)
      end
    end

    it 'API disable stores an empty array after consuming and preserves unrelated fields' do
      %i[totp backup].each do |kind|
        user.update!(otp_secret: secret, otp_required_for_login: true, consumed_timestep: nil,
                     failed_otp_attempts: 3, otp_locked_at: instant - 60)
        backup = user.generate_otp_backup_codes!.first
        user.save!
        code = kind == :totp ? ROTP::TOTP.new(secret).at(instant) : backup
        before = user.reload.attributes
        travel_to(instant) do
          delete '/api/v1/users/me/two_factor',
                 params: { password: 'wrong', otp_code: code }, headers: headers
          expect(response).to have_http_status(:unauthorized)
          expect(JSON.parse(response.body)['error']).to eq('password_required')
          expect(user.reload.attributes).to eq(before)
          delete '/api/v1/users/me/two_factor',
                 params: { password: 'secret123456', otp_code: code }, headers: headers
        end
        expect(response).to have_http_status(:ok)
        expect(user.reload.attributes.values_at('otp_secret', 'otp_required_for_login', 'otp_backup_codes')).to eq(
          [nil, false, []]
        )
        expected = kind == :totp ? instant.to_i / 30 : nil
        expect(user.consumed_timestep).to eq(expected)
        expect(user.updated_at).to eq(instant)
        changed = %w[otp_secret otp_required_for_login otp_backup_codes consumed_timestep updated_at]
        expect(user.attributes.except(*changed)).to eq(before.except(*changed))
      end
    end

    it 'API disable failure after consumption preserves the first save' do
      user.update!(otp_secret: secret, otp_required_for_login: true, failed_otp_attempts: 3)
      allow_any_instance_of(User).to receive(:update!).and_wrap_original do |original, changes|
        original.receiver.email = nil
        original.call(changes)
      end
      travel_to(instant) do
        delete '/api/v1/users/me/two_factor',
               params: { password: 'secret123456', otp_code: ROTP::TOTP.new(secret).at(instant) }, headers: headers
      end
      expect(response.status).to eq(422)
      expect(response.media_type).to eq('text/html')
      expect(response.body).to include('ActiveRecord::RecordInvalid', 'Email can')
      expect(user.reload.consumed_timestep).to eq(instant.to_i / 30)
      expect(user.otp_required_for_login).to be(true)
      expect(user.otp_secret).to eq(secret)
      expect(user.failed_otp_attempts).to eq(3)
    end
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
        freeze_time
      end
      after do
        Rack::Attack.enabled = false
        travel_back
      end

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
