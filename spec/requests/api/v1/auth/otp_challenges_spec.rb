# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/otp_challenge', type: :request do
  include ActiveSupport::Testing::TimeHelpers

  before do
    Rack::Attack.enabled = true
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(false)
  end

  after { Rack::Attack.enabled = false }

  let(:user) do
    u = create(:user, password: 'secret123456')
    u.otp_secret = User.generate_otp_secret
    u.otp_required_for_login = true
    u.save!
    u
  end
  let(:challenge_token) { Auth::IssueOtpChallengeToken.new(user).call }

  def current_totp
    ROTP::TOTP.new(user.otp_secret).now
  end

  context 'A11f API auth' do
    before { allow(DawarichSettings).to receive(:self_hosted?).and_return(true) }

    it 'A11f API auth preserves OTP success save order and Rails refusal effects' do
      secret = 'JBSWY3DPEHPK3PXP'
      totp = ROTP::TOTP.new(secret)
      epoch = Time.utc(2026, 10, 4, 12).to_i
      now = Time.at((0..1000).map { |n| epoch + n * 30 }.find { |at| totp.at(at).start_with?('0') }).utc
      owned_keys = []
      trace = []
      user.update!(otp_secret: secret)
      jobs = enqueued_jobs.dup
      stable = %w[encrypted_password sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip
                  last_sign_in_ip remember_created_at failed_attempts locked_at api_key created_at]
      allow_any_instance_of(Auth::VerifyOtpChallengeToken).to receive(:mark_consumed!).and_wrap_original do |method|
        trace << :mark
        method.call
      end
      subscriber = lambda do |_name, _start, _finish, _id, payload|
        sql = payload[:sql]
        next unless sql.start_with?('UPDATE "users"')

        trace << (sql.include?('failed_otp_attempts') ? :reset : :consume)
      end

      travel_to(now) do
        [false, true].each do |locked|
          backup = 'a11f-synthetic-backup'
          user.update_columns(consumed_timestep: nil, failed_otp_attempts: 4,
                              otp_locked_at: locked ? now - 60 : nil, updated_at: now - 1.day,
                              otp_backup_codes: [Devise::Encryptor.digest(User, backup)],
                              settings: { 'maps' => { 'url' => '  https://example.invalid  ' } })
          token = a11f_issue(user, owned_keys)
          baseline = user.reload.attributes.slice(*stable)
          trace.clear
          ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
            post '/api/v1/auth/otp_challenge',
                 params: { challenge_token: token, otp_code: "  #{locked ? backup : totp.at(now)}  " }, as: :json
          end
          expect(response.status).to eq(200)
          expect(JSON.parse(response.body)['api_key'] == user.api_key).to be(true)
          expect(trace).to eq(%i[consume mark reset])
          expect(user.reload.attributes.slice(*stable) == baseline).to be(true)
          expect(user.failed_otp_attempts).to eq(0)
          expect(user.otp_locked_at).to be_nil
          expect(user.updated_at).to eq(now)
          expect(user.settings).to eq('maps' => { 'url' => 'https://example.invalid' })
          expect(user.otp_backup_codes.empty?).to eq(locked)
          expect(user.consumed_timestep).to eq(locked ? nil : now.to_i / 30)
          expect(response.headers['Set-Cookie']).to be_nil
          expect(request.env['warden'].authenticated?(:user)).to be(false)
          expect(Rails.cache.read(owned_keys.last)).to be(true)
          post '/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: totp.at(now + 30) }
          expect(response.status).to eq(401)
          expect(user.reload.failed_otp_attempts).to eq(0)
        end

        [-30, 30].each do |drift|
          user.update_columns(consumed_timestep: nil, otp_locked_at: nil)
          post '/api/v1/auth/otp_challenge',
               params: { challenge_token: a11f_issue(user, owned_keys), otp_code: totp.at(now + drift) }
          expect(response.status).to eq(200)
          expect(user.reload.consumed_timestep).to eq((now.to_i + drift) / 30)
        end

        user.update_columns(consumed_timestep: nil, failed_otp_attempts: 0, otp_locked_at: nil)
        invalid = 'not-an-otp'
        [[invalid, 401], [totp.at(now).insert(3, ' '), 200], [totp.at(now - 60), 401]].each do |code, status|
          user.update_columns(consumed_timestep: nil)
          post '/api/v1/auth/otp_challenge', params: { challenge_token: a11f_issue(user, owned_keys), otp_code: code }
          expect(response.status).to eq(status)
          expect(user.reload.consumed_timestep).to eq(status == 200 ? now.to_i / 30 : nil)
        end
        token = a11f_issue(user, owned_keys)
        post '/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: totp.at(now) }
        expect(response.status).to eq(200)
        post '/api/v1/auth/otp_challenge',
             params: { challenge_token: a11f_issue(user, owned_keys), otp_code: totp.at(now) }
        expect(response.status).to eq(401)
        expect(user.reload.failed_otp_attempts).to eq(1)

        user.update_columns(consumed_timestep: nil, failed_otp_attempts: 4)
        post '/api/v1/auth/otp_challenge', params: { challenge_token: a11f_issue(user, owned_keys), otp_code: invalid }
        expect(response.status).to eq(401)
        expect(user.reload.failed_otp_attempts).to eq(5)
        expect(user.otp_locked_at).to be_nil
        user.update_columns(failed_otp_attempts: 9)
        owned_keys << "otp_lockout_email_throttle/user/#{user.id}"
        expect do
          post '/api/v1/auth/otp_challenge',
               params: { challenge_token: a11f_issue(user, owned_keys), otp_code: invalid }
        end.to have_enqueued_mail(UsersMailer, :otp_account_locked)
        expect(user.reload.failed_otp_attempts).to eq(10)
        expect(user.otp_locked_at).to eq(now)
        post '/api/v1/auth/otp_challenge',
             params: { challenge_token: a11f_issue(user, owned_keys), otp_code: totp.at(now) }
        expect(response.status).to eq(423)
        expect(user.reload.failed_otp_attempts).to eq(10)
        user.update_columns(otp_locked_at: now - 1801)
        post '/api/v1/auth/otp_challenge', params: { challenge_token: a11f_issue(user, owned_keys), otp_code: invalid }
        expect(response.status).to eq(401)
        expect(user.reload.failed_otp_attempts).to eq(1)
        expect(user.otp_locked_at).to be_nil

        user.update_columns(consumed_timestep: nil)
        token = a11f_issue(user, owned_keys)
        user.update_columns(otp_required_for_login: false)
        post '/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: totp.at(now) }
        expect(response.status).to eq(200)

        %i[mark reset render].each do |failure|
          user.update_columns(consumed_timestep: nil, failed_otp_attempts: 3, updated_at: now - 1.day)
          token = a11f_issue(user, owned_keys)
          target, method = case failure
                           when :mark then [Auth::VerifyOtpChallengeToken, :mark_consumed!]
                           when :reset then [User, :reset_failed_otp_attempts!]
                           else [Api::V1::Auth::OtpChallengesController, :render_auth_success]
                           end
          allow_any_instance_of(target).to receive(method).and_raise("a11f-after-#{failure}")
          expect do
            post '/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: totp.at(now) }
          end.to raise_error(RuntimeError, "a11f-after-#{failure}")
          expect(user.reload.consumed_timestep).to eq(now.to_i / 30)
          expect(user.updated_at).to eq(now)
          expect(user.failed_otp_attempts).to eq(failure == :render ? 0 : 3)
          expect(Rails.cache.exist?(owned_keys.last)).to eq(failure != :mark)
          allow_any_instance_of(target).to receive(method).and_call_original
        end
        expect(enqueued_jobs.size).to eq(jobs.size + 1)
      end
    ensure
      owned_keys&.each { |key| Rails.cache.delete(key) }
    end

    def a11f_issue(actor, owned_keys)
      token = Auth::IssueOtpChallengeToken.new(actor).call
      claims, = JWT.decode(token, Auth::InternalTokenSecret.call, true, algorithm: 'HS256')
      owned_keys << "otp_challenge:consumed:#{claims.fetch('jti')}"
      token
    end

    context 'committed source schedules' do
      before(:context) do
        @a11f_transactional_tests = self.class.use_transactional_tests
        self.class.use_transactional_tests = false
      end

      after(:context) { self.class.use_transactional_tests = @a11f_transactional_tests }

      let!(:user) do
        id = 911_510_001
        email = 'a11f-overlap@example.invalid'
        expect(User.unscoped.where('id = ? OR email = ?', id, email).exists?).to be(false)
        @a11f_owned_actor = [id, email]
        create(:user, id: id, email: email, password: 'a11f-synthetic-password',
                      otp_secret: 'JBSWY3DPEHPK3PXP', otp_required_for_login: true,
                      skip_auto_trial: true, skip_family_sync: true)
      end

      after do
        @a11f_keys&.each { |key| Rails.cache.delete(key) }
        if @a11f_owned_actor
          id, email = @a11f_owned_actor
          User.unscoped.where(id: id, email: email).delete_all
        end
      end

      it 'A11f API auth records concurrent stale verifiers and partial consumption outcomes' do
        @a11f_keys = []
        now = Time.utc(2026, 10, 4, 12)
        backup = 'a11f-stale-backup'
        marks = []
        allow_any_instance_of(Auth::VerifyOtpChallengeToken).to receive(:mark_consumed!).and_wrap_original do |original|
          result = original.call
          marks << [Thread.current[:a11f_worker], result]
          result
        end
        travel_to(now) do
          %i[totp backup].each do |kind|
            user.update_columns(consumed_timestep: nil, failed_otp_attempts: 4, otp_locked_at: nil,
                                otp_backup_codes: [Devise::Encryptor.digest(User, backup)], updated_at: now - 86_400)
            token = a11f_issue(user, @a11f_keys)
            code = kind == :totp ? user.current_otp : backup
            marks.clear
            a11f_prepared_requests(token, code) do |outcomes, observer, pids|
              expect(outcomes.map { |outcome| outcome[:status] }).to eq([200, 200])
              expect(outcomes.all? { |outcome| outcome[:subject] && !outcome[:cookie] }).to be(true)
              expect(marks).to eq([[0, true], [1, false]])
              observed = observer.select_one("SELECT * FROM users WHERE id=#{user.id}")
              expect(pids).not_to include(observer.select_value('SELECT pg_backend_pid()'))
              expect(observer.transaction_open?).to be(false)
              expect(observed['failed_otp_attempts']).to eq(0)
              expect(observed['consumed_timestep']).to eq(kind == :totp ? now.to_i / 30 : nil)
              expect(JSON.parse(observed['otp_backup_codes'])).to be_empty if kind == :backup
              expect(observed['sign_in_count']).to eq(0)
              expect(Rails.cache.read(@a11f_keys.last)).to be(true)
            end
            post '/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: user.current_otp }
            expect(response.status).to eq(401)
          end

          %i[mark reset].each do |failure|
            user.update_columns(consumed_timestep: nil, failed_otp_attempts: 4,
                                otp_backup_codes: [Devise::Encryptor.digest(User, backup)])
            token = a11f_issue(user, @a11f_keys)
            target, method = if failure == :mark
                               [Auth::VerifyOtpChallengeToken, :mark_consumed!]
                             else
                               [User, :reset_failed_otp_attempts!]
                             end
            allow_any_instance_of(target).to receive(method).and_raise("a11f-stale-after-#{failure}")
            expect do
              post '/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: backup }
            end.to raise_error(RuntimeError, "a11f-stale-after-#{failure}")
            expect(user.reload.otp_backup_codes).to be_empty
            expect(user.failed_otp_attempts).to eq(4)
            expect(Rails.cache.exist?(@a11f_keys.last)).to eq(failure == :reset)
            allow_any_instance_of(target).to receive(method).and_call_original
          end
        end
      end

      def a11f_prepared_requests(token, code)
        pool = ActiveRecord::Base.connection_pool
        expect(pool.size).to be >= 3
        observer = pool.checkout
        ready = Queue.new
        release = [Queue.new, Queue.new]
        allow_any_instance_of(User).to receive(:validate_and_consume_otp!).and_wrap_original do |original, value|
          index = Thread.current[:a11f_worker]
          unless index.nil?
            connection = ActiveRecord::Base.connection
            ready << [index, connection.select_value('SELECT pg_backend_pid()'), original.receiver.consumed_timestep]
            release[index].pop
          end
          original.call(value)
        end
        workers = [0, 1].map do |index|
          Thread.new do
            Thread.current[:a11f_worker] = index
            pool.with_connection do
              client = ActionDispatch::Integration::Session.new(Rails.application)
              client.post('/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: code }, as: :json)
              { status: client.response.status, subject: JSON.parse(client.response.body)['user_id'] == user.id,
                cookie: client.response.headers['Set-Cookie'].present? }
            rescue StandardError => e
              { error: e.class.name }
            end
          end
        end
        prepared = Timeout.timeout(5) { [ready.pop, ready.pop] }
        expect(prepared.map { |row| row[1] }.uniq.size).to eq(2)
        expect(prepared.map(&:last)).to eq([nil, nil])
        outcomes = workers.each_index.map do |index|
          release[index] << true
          workers[index].value
        end
        yield outcomes, observer, prepared.map { |row| row[1] }
      ensure
        release&.each { |queue| queue << true }
        workers&.each(&:join)
        pool.checkin(observer) if observer
      end
    end
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

  describe 'OTP lockout' do
    it 'returns 423 Locked when the account is locked' do
      user.update_columns(otp_locked_at: 1.minute.ago)
      post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: current_totp }
      expect(response).to have_http_status(:locked)
      expect(JSON.parse(response.body)['message']).to include('locked')
    end

    it 'increments failed_otp_attempts on a wrong code' do
      expect do
        post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: '000000' }
      end.to change { user.reload.failed_otp_attempts }.by(1)
    end

    it 'resets failed_otp_attempts on a successful login' do
      user.update_columns(failed_otp_attempts: 5)
      post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: current_totp }
      expect(response).to have_http_status(:ok)
      expect(user.reload.failed_otp_attempts).to eq(0)
    end

    it 'enqueues the lockout email when the threshold is reached' do
      user.update_columns(failed_otp_attempts: User::MAX_FAILED_OTP_ATTEMPTS - 1)
      expect do
        post '/api/v1/auth/otp_challenge', params: { challenge_token: challenge_token, otp_code: '000000' }
      end.to have_enqueued_mail(UsersMailer, :otp_account_locked)
    end
  end

  describe 'brute-force protection keyed on challenge_token' do
    before { freeze_time }
    after { travel_back }

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
