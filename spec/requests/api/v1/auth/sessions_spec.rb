# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/login', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let!(:user) { create(:user, email: 'me@example.com', password: 'secret123456') }

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    # The login throttle is cloud-only — self-hosted instances skip it.
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  after { Rack::Attack.enabled = false }

  context 'A11f API auth' do
    around { |example| Time.use_zone('UTC') { example.run } }
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'A11f API auth preserves password login responses without web sign-in effects' do
      travel_to(Time.utc(2026, 10, 4, 12)) do
        caller = create(:user, email: 'a11f-caller@example.com', settings: { 'timezone' => 'Europe/Berlin' })
        family = create(:family, creator: caller)
        create(:family_membership, :owner, family: family, user: caller)
        create(:family_membership, family: family, user: user)
        keys = %w[user_id email api_key status plan effective_plan subscription_source active_until]
        jobs = enqueued_jobs.dup
        fields = %w[encrypted_password sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip
                    last_sign_in_ip remember_created_at failed_attempts locked_at failed_otp_attempts
                    otp_locked_at consumed_timestep api_key settings created_at updated_at]

        User.statuses.each_key do |status|
          User.plans.each_key do |plan|
            User.subscription_sources.each_key do |source|
              user.update_columns(status: User.statuses.fetch(status), plan: User.plans.fetch(plan),
                                  subscription_source: User.subscription_sources.fetch(source),
                                  locked_at: Time.current, failed_attempts: 7, failed_otp_attempts: 4,
                                  active_until: Time.utc(2020, 1, 2, 3, 4, 5))
              baseline = user.reload.attributes.slice(*fields)
              post '/api/v1/auth/login',
                   params: { email: '  ME@Example.com  ', password: 'secret123456' },
                   headers: { 'Authorization' => "Bearer #{caller.api_key}", 'Accept-Language' => 'de' }, as: :json
              expect(response.status).to eq(200)
              body = JSON.parse(response.body)
              expect(body.keys).to eq(keys)
              expect(body['user_id']).to eq(user.id)
              expect(body['email']).to eq(user.email)
              expect(body['api_key'] == user.api_key).to be(true)
              expect(body.slice('status', 'plan', 'effective_plan', 'subscription_source', 'active_until')).to eq(
                'status' => status, 'plan' => plan, 'effective_plan' => plan,
                'subscription_source' => source, 'active_until' => '2020-01-02T04:04:05+01:00'
              )
              expect(response.headers['X-Dawarich-Response']).to eq("Hey, I'm alive and authenticated!")
              expect(response.headers['X-Dawarich-Version']).to eq(APP_VERSION)
              expect(response.headers['Content-Type']).to eq('application/json; charset=utf-8')
              expect(response.headers['Cache-Control']).to eq('max-age=0, private, must-revalidate')
              expect(response.headers['ETag']).to match(%r{\AW/"[0-9a-f]{32}"\z})
              expect(response.headers.keys.grep(/\AX-RateLimit-/i)).to be_empty
              expect(response.headers['Set-Cookie']).to be_nil
              expect(user.reload.attributes.slice(*fields) == baseline).to be(true)
              expect(request.env['warden'].authenticated?(:user)).to be(false)
            end
          end
        end

        user.update_columns(active_until: Time.utc(2026, 1, 2, 3, 4, 5, 123_456))
        post '/api/v1/auth/login', params: { email: user.email, password: 'secret123456' },
             headers: { 'Authorization' => '' }, as: :json
        expect(JSON.parse(response.body)['active_until']).to eq('2026-01-02T03:04:05Z')
        user.update_columns(active_until: nil)
        post '/api/v1/auth/login', params: { email: user.email, password: 'secret123456', api_key: caller.api_key }
        expect(response.status).to eq(200)
        expect(JSON.parse(response.body)['active_until']).to be_nil
        expect(JSON.parse(response.body)['user_id']).to eq(user.id)
        expect(response.headers['Set-Cookie']).to be_nil

        [nil, 'unknown-a11f-key'].each do |key|
          post '/api/v1/auth/login', params: { email: user.email, password: 'secret123456', api_key: key }
          expect(response.status).to eq(200)
          expect(response.headers['X-Dawarich-Response']).to eq("Hey, I'm alive!")
        end

        failures = [
          { email: user.email, password: 'wrong' }, { email: 'absent-a11f@example.com', password: 'wrong' },
          { email: nil, password: 'secret123456' }, { email: '  ', password: 'secret123456' },
          { email: user.email, password: nil }, { email: user.email, password: '' }
        ]
        failures.each do |params|
          baseline = user.reload.attributes
          messages = %w[en de].map do |locale|
            post '/api/v1/auth/login', params: params, headers: { 'Accept-Language' => locale }, as: :json
            expect(response.status).to eq(401)
            expect(response.headers['Set-Cookie']).to be_nil
            JSON.parse(response.body)
          end
          expect(messages.first).to eq(messages.last)
          expect(user.reload.attributes == baseline).to be(true)
        end

        [["#{'a' * 72}x", "#{'a' * 72}y"], %w[pässwörd-旅行-123456 pässwörd-旅行-123456]].each do |stored, supplied|
          user.update!(password: stored, password_confirmation: stored)
          baseline = user.reload.attributes
          post '/api/v1/auth/login', params: { email: user.email, password: supplied }, as: :json
          expect(response.status).to eq(200)
          expect(user.reload.attributes == baseline).to be(true)
        end

        user.update!(otp_secret: User.generate_otp_secret, otp_required_for_login: true)
        [false, true].each do |available|
          allow(DawarichSettings).to receive(:two_factor_available?).and_return(available)
          baseline = user.reload.attributes
          post '/api/v1/auth/login', params: { email: user.email, password: 'pässwörd-旅行-123456' }, as: :json
          body = JSON.parse(response.body)
          expect(response.status).to eq(available ? 202 : 200)
          if available
            expect(body.keys).to eq(%w[two_factor_required challenge_token ttl])
            expect(body['two_factor_required']).to be(true)
            expect(body['ttl']).to eq(300)
            claims, = JWT.decode(body['challenge_token'], Auth::InternalTokenSecret.call, true, algorithm: 'HS256')
            expect(claims['user_id']).to eq(user.id)
            expect(claims['purpose']).to eq('otp_challenge')
          else
            expect(body['api_key'] == user.api_key).to be(true)
          end
          expect(response.headers['Set-Cookie']).to be_nil
          expect(user.reload.attributes == baseline).to be(true)
        end

        user.update_columns(otp_required_for_login: false)
        post '/api/v1/auth/login', params: { email: user.email, password: 'pässwörd-旅行-123456' }
        expect(response.status).to eq(200)
        user.update_columns(deleted_at: Time.current)
        post '/api/v1/auth/login', params: { email: user.email, password: 'pässwörd-旅行-123456' }, as: :json
        expect(response.status).to eq(401)
        expect(enqueued_jobs).to eq(jobs)
      end
    end
  end

  it 'returns 200 with api_key on correct credentials' do
    post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['api_key']).to eq(user.api_key)
    expect(body['user_id']).to eq(user.id)
    expect(body).not_to have_key('two_factor_required')
  end

  it 'returns 401 on wrong password' do
    post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'wrong' }
    expect(response).to have_http_status(:unauthorized)
  end

  it 'returns 401 on unknown email' do
    post '/api/v1/auth/login', params: { email: 'nope@example.com', password: 'secret123456' }
    expect(response).to have_http_status(:unauthorized)
  end

  describe 'email whitespace/case normalisation on lookup' do
    # Mirrors Devise's `config.strip_whitespace_keys = [:email]` and the
    # `logins/api_email` Rack::Attack throttle's `downcase.strip` key, so the
    # controller's lookup must strip *and* downcase the param the same way.

    it 'logs in when the email has leading/trailing whitespace' do
      post '/api/v1/auth/login',
           params: { email: '  me@example.com  ', password: 'secret123456' }
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['api_key']).to eq(user.api_key)
      expect(body['user_id']).to eq(user.id)
    end

    it 'still runs a bcrypt comparison on the padded unknown-email path' do
      # The constant-time dummy-password comparison must still fire when the
      # (stripped) lookup misses, so padded unknown emails don't leak account
      # existence through response timing.
      expect(BCrypt::Password).to receive(:new).and_call_original.at_least(:once)
      post '/api/v1/auth/login',
           params: { email: '  no-such-user@example.com  ', password: 'whatever' }
      expect(response).to have_http_status(:unauthorized)
    end

    it 'still returns 401 when the email param is missing or blank' do
      post '/api/v1/auth/login', params: { password: 'secret123456' }
      expect(response).to have_http_status(:unauthorized)
      post '/api/v1/auth/login', params: { email: '   ', password: 'secret123456' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'shared API middleware' do
    # BaseController inherits from ApiController, so the version header and
    # rate-limit header pipeline are applied consistently across all API
    # endpoints. These are served by ApplicationController-level hooks
    # (set_version_header, set_rate_limit_headers) that would otherwise be
    # absent if BaseController inherited from ActionController::API directly.
    it 'sends the X-Dawarich-Version header from ApiController' do
      post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
      expect(response.headers['X-Dawarich-Version']).to be_present
      expect(response.headers['X-Dawarich-Response']).to be_present
    end
  end

  describe 'timing-attack resistance' do
    it 'runs a bcrypt comparison on the unknown-email path (constant time)' do
      # Observable behavior: a bcrypt password verification happens even when
      # no user exists for the submitted email. We assert this by watching
      # BCrypt::Password#is_password? — it is the heavy operation that, if
      # skipped, reveals account existence through response timing.
      expect(BCrypt::Password).to receive(:new).and_call_original.at_least(:once)
      post '/api/v1/auth/login', params: { email: 'no-such-user@example.com', password: 'whatever' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it 'includes current plan/status/subscription_source on success' do
    user.update!(status: :active, plan: :pro, subscription_source: :paddle, active_until: 1.year.from_now)
    post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
    body = JSON.parse(response.body)
    expect(body['plan']).to eq('pro')
    expect(body['status']).to eq('active')
    expect(body['subscription_source']).to eq('paddle')
  end

  context 'user has 2FA enabled' do
    before do
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(true)
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'returns 202 with a challenge_token and no api_key' do
      post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
      expect(response).to have_http_status(:accepted)
      body = JSON.parse(response.body)
      expect(body['two_factor_required']).to be true
      expect(body['challenge_token']).to be_present
      expect(body['ttl']).to eq(300)
      expect(body).not_to have_key('api_key')
    end

    it 'still returns 401 on wrong password (does not reveal 2FA state)' do
      post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'wrong' }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'DawarichSettings.two_factor_available? is false' do
    before do
      allow(DawarichSettings).to receive(:two_factor_available?).and_return(false)
      user.otp_secret = User.generate_otp_secret
      user.otp_required_for_login = true
      user.save!
    end

    it 'logs the user in normally, ignoring the otp flag' do
      post '/api/v1/auth/login', params: { email: 'me@example.com', password: 'secret123456' }
      expect(response).to have_http_status(:ok)
    end
  end

  # The published API contract for POST /api/v1/auth/login is application/json
  # (spec/swagger/api/v1/auth/sessions_controller_spec.rb `consumes 'application/json'`),
  # and form-encoded bodies diverge one middleware layer below from JSON at the
  # rack-attack layer (Rack::Request#params ignores application/json). Every
  # brute-force case below is therefore exercised against the production JSON
  # shape, with one form-encoded guard so the legacy body parser is not lost.
  describe 'brute-force protection' do
    # Rack::Attack throttle windows are aligned to epoch minutes, so a
    # multi-second burst of slow bcrypt requests can straddle a window
    # boundary and split the counter across two windows. Freeze time so
    # every request in an example lands in the same window.
    before { freeze_time }
    after { travel_back }

    it 'throttles repeated JSON attempts against the same email to 5 per minute' do
      5.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
      post '/api/v1/auth/login',
           params: { email: 'me@example.com', password: 'wrong' }, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'normalises email casing/whitespace so case variations share the same bucket (JSON body)' do
      5.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }, as: :json
      end
      post '/api/v1/auth/login',
           params: { email: '  ME@Example.com  ', password: 'wrong' }, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'throttles repeated JSON attempts from the same IP across many emails to 20 per minute' do
      # 20 attempts from this IP, each with a different email so the email throttle
      # does not fire (each email still under the per-email limit of 5).
      20.times do |i|
        post '/api/v1/auth/login',
             params: { email: "user#{i}@example.com", password: 'wrong' }, as: :json
      end
      post '/api/v1/auth/login',
           params: { email: 'user-final@example.com', password: 'wrong' }, as: :json
      expect(response).to have_http_status(:too_many_requests)
    end

    it 'returns the shared rate-limit error envelope when throttled' do
      6.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }, as: :json
      end
      expect(response).to have_http_status(:too_many_requests)
      body = JSON.parse(response.body)
      expect(body['error']).to eq('rate_limit_exceeded')
      expect(response.headers['Retry-After']).to be_present
    end

    it 'still permits a successful login while under the limit' do
      4.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }, as: :json
      end
      post '/api/v1/auth/login',
           params: { email: 'me@example.com', password: 'secret123456' }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'still throttles form-encoded bodies (legacy/client form posts)' do
      5.times do
        post '/api/v1/auth/login',
             params: { email: 'me@example.com', password: 'wrong' }
        expect(response).to have_http_status(:unauthorized)
      end
      post '/api/v1/auth/login',
           params: { email: 'me@example.com', password: 'wrong' }
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
