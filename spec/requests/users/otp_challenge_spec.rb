# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Users::Sessions OTP Challenge', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:password) { 'test_password_123' }
  let(:user) { create(:user, password: password) }

  before do
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
  end

  context 'A11d source oracle' do
    let(:now) { Time.utc(2026, 10, 4, 12) }
    let(:synthetic_secret) { 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ' }

    around do |example|
      previous = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      example.run
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end

    before do
      user.update!(otp_secret: synthetic_secret, otp_required_for_login: true)
    end

    it 'preserves exact-email challenge initialization without authentication effects' do
      travel_to(now) do
        unchanged = user.reload.attributes
        jobs = enqueued_jobs.size
        [nil, '0', '1', 'true'].each do |remember|
          client = otp_oracle_client('otp_failed_attempts' => 3, 'user_return_to' => '/trips',
                                     'devise.synthetic' => 'retained', 'locale' => 'en')
          before = otp_oracle_session(client)
          otp_oracle_start(client, email: user.email, remember: remember)
          pending = otp_oracle_session(client)

          expect(client.response.status).to eq(422)
          expect(pending.slice('otp_user_id', 'otp_challenge_at', 'otp_remember_me', 'otp_failed_attempts'))
            .to eq('otp_user_id' => user.id, 'otp_challenge_at' => now.to_i,
                   'otp_remember_me' => remember == '1', 'otp_failed_attempts' => 3)
          expect(pending.slice('session_id', '_csrf_token', 'locale', 'user_return_to', 'devise.synthetic') ==
                 before.slice('session_id', '_csrf_token', 'locale', 'user_return_to', 'devise.synthetic')).to be(true)
          expect(pending.keys).not_to include('warden.user.user.key')
          expect(client.cookies['remember_user_token']).to be_nil
          otp_oracle_start(client, email: user.email, remember: remember)
          expect(otp_oracle_session(client)['otp_failed_attempts']).to eq(3)
          expect(user.reload.attributes).to eq(unchanged)
          expect(enqueued_jobs.size).to eq(jobs)
        end

        [user.email.upcase, " #{user.email} "].each do |email|
          user.update_columns(failed_attempts: 0)
          client = otp_oracle_client
          otp_oracle_start(client, email: email)
          expect(otp_oracle_session(client).keys).not_to include('otp_user_id')
        end
        ['wrong', ''].each do |attempt|
          user.update_columns(failed_attempts: 0)
          client = otp_oracle_client
          otp_oracle_start(client, email: user.email, password: attempt)
          expect(otp_oracle_session(client).keys).not_to include('otp_user_id')
        end
        allow(DawarichSettings).to receive(:two_factor_available?).and_return(false)
        user.update_columns(failed_attempts: 0)
        client = otp_oracle_client
        otp_oracle_start(client, email: user.email)
        expect(otp_oracle_session(client).keys).not_to include('otp_user_id')

        allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(true)
        stub_const('ALLOW_EMAIL_PASSWORD_LOGIN', false)
        client = otp_oracle_client
        otp_oracle_start(client, email: user.email)
        expect(client.response.status).to eq(302)
        expect(otp_oracle_session(client).keys).not_to include('otp_user_id')
      end
    end

    it 'completes OTP with source save callback and redirect ordering' do
      travel_to(now) do
        other = create(:user)
        other_before = other.reload.attributes
        [false, true].each do |remember|
          [nil, now - 1.minute].each do |otp_lock|
            backup = 'a11d-synthetic-backup-code'
            user.update_columns(consumed_timestep: nil, failed_otp_attempts: 4, otp_locked_at: otp_lock,
                                failed_attempts: 2, locked_at: nil, unlock_token: 'synthetic-unlock',
                                remember_created_at: now - 1.day,
                                otp_backup_codes: [Devise::Encryptor.digest(User, backup)])
            client = otp_oracle_client('user_return_to' => '/trips', 'devise.synthetic' => 'discarded',
                                       'otp_failed_attempts' => 2, 'locale' => 'en',
                                       'warden.user.user.session' => { 'last_request_at' => 42 })
            otp_oracle_start(client, email: user.email, remember: remember ? '1' : '0')
            pending = otp_oracle_session(client)
            otp_oracle_seed(client, pending.merge('flash' => {
                                                    'discard' => ['alert'],
                                                    'flashes' => { 'alert' => 'discarded', 'warning' => 'retained' }
                                                  }))
            before = user.reload.attributes
            writes = []
            subscriber = lambda do |_name, _start, _finish, _id, payload|
              writes << payload[:sql] if payload[:sql].start_with?('UPDATE "users"')
            end
            code = otp_lock ? backup : user.current_otp
            ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
              client.post('/users/otp_challenge', params: { otp_attempt: code,
                                                          authenticity_token: otp_oracle_csrf(client) })
            end
            completed = otp_oracle_session(client)
            expect(client.response.status).to eq(302)
            expect(client.response.location).to end_with('/trips')
            expect(completed.keys & %w[otp_user_id otp_challenge_at otp_failed_attempts otp_remember_me
                                       user_return_to devise.synthetic]).to be_empty
            expect(completed['warden.user.user.key']).to eq([[user.id], user.authenticatable_salt])
            expect(completed['session_id']).not_to eq(pending['session_id'])
            expect(completed['_csrf_token'] == pending['_csrf_token']).to be(true)
            expect(completed['locale']).to eq('en')
            expect(completed['warden.user.user.session']).to eq('last_request_at' => 42)
            expect(completed.dig('flash', 'flashes', 'notice')).to eq('Signed in successfully.')
            expect(completed.dig('flash', 'flashes').keys).not_to include('alert', 'warning')
            expect(user.reload.failed_attempts).to eq(0)
            expect(user.unlock_token).to eq('synthetic-unlock')
            expect(user.failed_otp_attempts).to eq(0)
            expect(user.otp_locked_at).to be_nil
            expect(user.sign_in_count).to eq(before['sign_in_count'] + 1)
            expect(user.current_sign_in_at).to eq(now)
            expect(user.last_sign_in_at).to eq(before['current_sign_in_at'] || now)
            expect(user.remember_created_at).to eq(remember ? now - 1.day : before['remember_created_at'])
            expect(client.cookies['remember_user_token'].present?).to eq(remember)
            consumption = writes.index { |sql| sql.include?(otp_lock ? 'otp_backup_codes' : 'consumed_timestep') }
            reset = writes.index { |sql| sql.include?('failed_otp_attempts') }
            track = writes.index { |sql| sql.include?('sign_in_count') }
            expect(consumption).to be < reset
            expect(reset).to be < track
          end
        end

        [now.to_i - 300, nil, now.to_i + 60].each do |timestamp|
          user.update_columns(consumed_timestep: nil)
          client = otp_oracle_client('otp_user_id' => user.id, 'otp_challenge_at' => timestamp,
                                     'otp_remember_me' => false, 'otp_failed_attempts' => 2)
          client.post('/users/otp_challenge', params: { otp_attempt: user.current_otp,
                                                      authenticity_token: otp_oracle_csrf(client) })
          completed = otp_oracle_session(client)
          expect(client.response.status).to eq(302)
          expect(completed.keys & %w[otp_user_id otp_challenge_at otp_failed_attempts otp_remember_me]).to be_empty
          expect(completed.key?('warden.user.user.key')).to eq(timestamp == now.to_i + 60)
        end

        client = otp_oracle_client('otp_user_id' => other.id + user.id + 999_999,
                                   'otp_challenge_at' => now.to_i)
        client.post('/users/otp_challenge', params: { otp_attempt: user.current_otp,
                                                    authenticity_token: otp_oracle_csrf(client) })
        expect(client.response.location).to end_with('/users/sign_in')

        user.update_columns(consumed_timestep: nil, locked_at: now - 2.hours,
                            unlock_token: 'synthetic-expired-unlock', failed_attempts: 4)
        client = otp_oracle_client('otp_user_id' => user.id, 'otp_challenge_at' => now.to_i)
        client.post('/users/otp_challenge', params: { otp_attempt: user.current_otp,
                                                    authenticity_token: otp_oracle_csrf(client) })
        expect(client.response.status).to eq(302)
        expect(user.reload.failed_attempts).to eq(0)
        expect(user.locked_at).to eq(now - 2.hours)
        expect(user.unlock_token).to eq('synthetic-expired-unlock')

        user.update_columns(consumed_timestep: nil, locked_at: now - 1.minute, failed_attempts: 5)
        client = otp_oracle_client('otp_user_id' => user.id, 'otp_challenge_at' => now.to_i)
        client.post('/users/otp_challenge', params: { otp_attempt: user.current_otp,
                                                    authenticity_token: otp_oracle_csrf(client) })
        expect(client.response.location).to end_with('/users/sign_in')
        expect(user.reload.consumed_timestep).to eq(now.to_i / 30)
        expect(user.failed_attempts).to eq(5)
        expect(user.locked_at).to eq(now - 1.minute)

        user.update_columns(locked_at: nil, otp_required_for_login: false, consumed_timestep: nil)
        allow(DawarichSettings).to receive(:two_factor_available?).and_return(false)
        client = otp_oracle_client('otp_user_id' => user.id, 'otp_challenge_at' => now.to_i)
        client.post('/users/otp_challenge', params: { otp_attempt: user.current_otp,
                                                    authenticity_token: otp_oracle_csrf(client) })
        expect(client.response.status).to eq(302)
        expect(otp_oracle_session(client).keys).to include('warden.user.user.key')

        user.update_columns(consumed_timestep: nil, failed_otp_attempts: 3)
        client = otp_oracle_client('otp_user_id' => user.id, 'otp_challenge_at' => now.to_i)
        allow_any_instance_of(User).to receive(:reset_failed_otp_attempts!).and_raise('a11d-after-consumption')
        expect do
          client.post('/users/otp_challenge', params: { otp_attempt: user.current_otp,
                                                      authenticity_token: otp_oracle_csrf(client) })
        end
          .to raise_error(RuntimeError, 'a11d-after-consumption')
        expect(user.reload.consumed_timestep).to eq(now.to_i / 30)
        expect(user.failed_otp_attempts).to eq(3)
        expect(other.reload.attributes).to eq(other_before)
      end
    end

    def otp_oracle_client(extra = {})
      client = ActionDispatch::Integration::Session.new(Rails.application)
      client.get('/users/sign_in')
      otp_oracle_seed(client, otp_oracle_session(client).merge(extra))
      client
    end

    def otp_oracle_seed(client, data)
      jar = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
      jar.encrypted['_dawarich_session'] = { value: data }
      client.cookies['_dawarich_session'] = jar['_dawarich_session']
    end

    def otp_oracle_session(client)
      jar = ActionDispatch::Cookies::CookieJar.build(
        ActionDispatch::Request.new(Rails.application.env_config.dup),
        '_dawarich_session' => client.cookies['_dawarich_session']
      )
      jar.encrypted['_dawarich_session']
    end

    def otp_oracle_csrf(client)
      Nokogiri::HTML5(client.response.body).at_css('meta[name="csrf-token"]')['content']
    end

    def otp_oracle_start(client, email:, password: self.password, remember: nil)
      client.post('/users/sign_in', params: { authenticity_token: otp_oracle_csrf(client),
                                             user: { email: email, password: password, remember_me: remember } })
    end
  end

  describe 'login with 2FA enabled' do
    before do
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.generate_otp_backup_codes!
      user.save!
    end

    context 'when password is correct but no OTP provided' do
      it 'shows OTP challenge page and sets session timestamp' do
        post user_session_path, params: { user: { email: user.email, password: password } }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Authentication code')
        expect(session[:otp_user_id]).to eq(user.id)
        expect(session[:otp_challenge_at]).to be_present
      end
    end

    context 'with a stashed pending-import ticket' do
      let!(:pending) { create(:pending_import, :with_file) }

      before do
        allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
        allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
        allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
        stub_const('MANAGER_URL', 'https://manager.example.com')
      end

      it 'claims the ticket after a successful 2FA sign-in' do
        get "/users/sign_up?import_ticket=#{pending.claim_ticket}"
        expect(session[:pending_import_ticket]).to eq(pending.claim_ticket)

        post user_session_path, params: { user: { email: user.email, password: password } }

        expect { post user_otp_challenge_path, params: { otp_attempt: user.current_otp } }
          .to change(user.imports, :count).by(1)

        expect(pending.reload.claimed_by_user_id).to eq(user.id)
      end
    end

    context 'when OTP challenge is submitted with valid code' do
      it 'signs in the user and clears session' do
        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: user.current_otp }

        expect(response).to redirect_to(root_path)
        expect(session[:otp_user_id]).to be_nil
        expect(session[:otp_challenge_at]).to be_nil
      end
    end

    context 'when OTP challenge is submitted with invalid code' do
      it 'shows error' do
        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: '000000' }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include('Invalid two-factor code')
      end

      it 'kicks the user back to sign-in after 5 invalid attempts' do
        post user_session_path, params: { user: { email: user.email, password: password } }

        4.times do
          post user_otp_challenge_path, params: { otp_attempt: '000000' }
          expect(response).to have_http_status(:unprocessable_entity)
        end

        post user_otp_challenge_path, params: { otp_attempt: '000000' }
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to include('Too many invalid')
      end

      it 'increments failed_otp_attempts' do
        post user_session_path, params: { user: { email: user.email, password: password } }
        expect do
          post user_otp_challenge_path, params: { otp_attempt: '000000' }
        end.to change { user.reload.failed_otp_attempts }.by(1)
      end
    end

    context 'when the account is locked' do
      before do
        user.update_columns(otp_locked_at: 1.minute.ago)
        post user_session_path, params: { user: { email: user.email, password: password } }
      end

      it 'redirects to login with a locked message' do
        post user_otp_challenge_path, params: { otp_attempt: user.current_otp }
        expect(response).to redirect_to(new_user_session_path)
        expect(flash[:alert]).to include('locked')
      end
    end

    context 'when OTP succeeds after previous failures' do
      it 'resets the failed_otp_attempts counter' do
        user.update_columns(failed_otp_attempts: 5)
        post user_session_path, params: { user: { email: user.email, password: password } }
        post user_otp_challenge_path, params: { otp_attempt: user.current_otp }
        expect(user.reload.failed_otp_attempts).to eq(0)
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
        expect(flash[:alert]).to include('expired')
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

  describe 'when 2FA is not available on the instance' do
    before do
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(false)
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'skips OTP challenge and signs in normally' do
      post user_session_path, params: { user: { email: user.email, password: password } }

      # Without 2FA available, Devise handles auth directly (may succeed or fail
      # depending on strategy, but should NOT show OTP challenge)
      expect(session[:otp_user_id]).to be_nil
    end
  end
end
