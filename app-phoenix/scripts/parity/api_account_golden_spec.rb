# frozen_string_literal: true

require 'rails_helper'
require_relative 'places_golden_support'
require_relative '../../test/support/auth/api_jwt_fixture'

module ApiAccountGoldenOracle
  TABLES = %w[users families family_memberships instance_settings].freeze
  AFTER = TABLES.freeze
  OWNER = 954_001
  OTHER = 954_002
  KEY = 'phoenix-a4rest-account-synthetic'
  NOW = Time.utc(2026, 10, 3, 12)
  STAMP = '2026-09-01 12:00:00.123456'
  SEQUENCES = {}.freeze
  P = '/api/v1/users/me'
  T = "#{P}/two_factor".freeze
  JSON_TYPE = { 'Content-Type' => 'application/json' }.freeze

  def self.setups = @setups ||= {}
end

require_relative 'api_account_golden_cases'

RSpec.describe 'Phoenix fixture: golden account API requests', type: :request do
  include ActiveSupport::Testing::TimeHelpers
  include PlacesGoldenSupport

  context 'A12f2 H mobile closure' do
    it 'records standalone mobile login registration and provider refusals' do
      prior_attack = Rack::Attack.enabled
      Rack::Attack.enabled = false
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(DawarichSettings).to receive(:oidc_enabled?).and_return(false)
      allow(DawarichSettings).to receive(:registration_enabled?).and_return(true)
      rows = []
      cases = [
        ['login-invalid', '/api/v1/auth/login', { email: 'missing-h@example.invalid', password: 'wrong' }],
        ['otp-invalid', '/api/v1/auth/otp_challenge', { challenge_token: 'invalid', otp_code: '012345' }],
        ['registration-invalid', '/api/v1/auth/register',
         { email: 'invalid', password: '', password_confirmation: '' }],
        ['apple-blank', '/api/v1/auth/apple', { id_token: '' }],
        ['google-blank', '/api/v1/auth/google', { id_token: '' }]
      ]
      cases.each do |name, path, params|
        post path, params: params, as: :json, headers: { 'X-Dawarich-Client' => 'ios' }
        rows << { 'name' => name, 'status' => response.status, 'body' => JSON.parse(response.body) }
      end
      path = Rails.root.join('app-phoenix/test/fixtures/auth/a12f2h/closure.json')
      encoded = "#{JSON.pretty_generate(rows)}\n"
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        FileUtils.mkdir_p(path.dirname)
        File.write(path, encoded)
      else
        expect(path.read).to eq(encoded)
      end
    ensure
      Rack::Attack.enabled = prior_attack
    end
  end

  context 'A11f API auth' do
    before(:context) do
      @api_auth_transactional_tests = self.class.use_transactional_tests
      self.class.use_transactional_tests = false
    end

    after(:context) { self.class.use_transactional_tests = @api_auth_transactional_tests }

    it 'A11f API auth writes the complete deterministic source corpus' do
      corpus, vectors = api_auth_corpus
      oracle = ApiAccountGoldenOracle
      matrix = User.statuses.keys.product(User.plans.keys, User.subscription_sources.keys).map do |values|
        "enums-#{values.join('-')}"
      end
      expect(corpus.fetch('login').map { |row| row.fetch('name') }.sort)
        .to eq((oracle::API_AUTH_LOGIN_NAMES + matrix).sort)
      expect(corpus.fetch('challenge').map { |row| row.fetch('name') }.sort)
        .to eq(oracle::API_AUTH_CHALLENGE_NAMES.sort)
      expect(corpus.keys.sort).to eq(%w[cache challenge exclusions login races tokens])
      corpus.each do |name, rows|
        path = Rails.root.join('app-phoenix/test/fixtures/auth/api_auth', "#{name}.json")
        encoded = "#{Oj.dump(rows, mode: :strict, indent: 2, float_precision: 0).rstrip}\n"
        if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
          FileUtils.mkdir_p(path.dirname)
          File.write(path, encoded)
        else
          expect(path.read == encoded).to be(true), "A11f #{name} corpus differs from source"
        end
      end
      encoded = ApiJwtFixture.encode(vectors)
      JSON.parse(encoded).fetch('vectors').zip(vectors.fetch('vectors')).each do |stored, original|
        restored = stored['token'].is_a?(Array) ? stored['token'].join('.') : stored['token']
        expect(restored).to eq(original['token']), original.fetch('name')
      end
      if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
        File.write(ApiJwtFixture.path, encoded)
      else
        expect(File.read(ApiJwtFixture.path)).to eq(encoded), 'A11f Rails JWT vectors differ from source'
      end
    end

    def api_auth_corpus
      prior_cache = Rails.cache
      prior_attack = Rack::Attack.enabled
      @api_auth_now = ApiJwtFixture.now
      @api_auth_keys = []
      @api_auth_actors = []
      @api_auth_redis = Redis.new(url: "#{ENV.fetch('REDIS_URL')}/0", driver: :ruby)
      Rails.cache = ActiveSupport::Cache::RedisCacheStore.new(redis: @api_auth_redis,
                                                              error_handler: ->(**_failure) {})
      Rack::Attack.enabled = false
      allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('JWT_SECRET_KEY').and_return(ApiJwtFixture.secret('jwt'))
      allow(ENV).to receive(:[]).with('AUTH_JWT_SECRET_KEY').and_return(ApiJwtFixture.secret('mobile'))
      allow(Rails.application).to receive(:secret_key_base).and_return(ApiJwtFixture.secret('fallback'))
      matrix = User.statuses.keys.product(User.plans.keys, User.subscription_sources.keys).map do |status, plan, source|
        { name: "enums-#{status}-#{plan}-#{source}", actor_status: status, plan: plan, source: source }
      end
      corpus = {}
      Time.use_zone('UTC') do
        corpus['login'] = (ApiAccountGoldenOracle::API_AUTH_LOGIN_CASES + matrix).map do |entry|
          api_auth_http_row(entry, :login)
        end
        corpus['challenge'] = ApiAccountGoldenOracle::API_AUTH_CHALLENGE_CASES.map do |entry|
          api_auth_http_row(entry, :challenge)
        end
        corpus['exclusions'] = api_auth_exclusion_cases.map { |entry| api_auth_http_row(entry, :login) }
        corpus['cache'] = api_auth_cache_rows
        corpus['races'] = %i[totp backup].map { |kind| api_auth_race_row(kind) }
        corpus['tokens'], vectors = api_auth_token_rows
        return [corpus, vectors]
      end
    ensure
      api_auth_cleanup
      @api_auth_redis&.close
      Rails.cache = prior_cache
      Rack::Attack.enabled = prior_attack
    end

    def api_auth_actor(entry, otp: false)
      id = ApiJwtFixture.user_id
      email = 'a11f-source@example.invalid'
      expect(User.unscoped.where('id = ? OR email = ?', id, email).exists?).to be(false)
      @api_auth_actors << [id, [email, 'a11f-changed@example.invalid']]
      user = create(:user, id: id, email: email, password: entry.fetch(:password, 'a11f-source-password'),
                          status: entry.fetch(:actor_status, :active), plan: entry.fetch(:plan, :pro),
                          subscription_source: entry.fetch(:source, :none), active_until: nil,
                          settings: { 'timezone' => 'UTC' }, skip_auto_trial: true, skip_family_sync: true)
      user.otp_secret = 'JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP'
      user.otp_required_for_login = entry.fetch(:otp, otp)
      user.otp_backup_codes = [Devise::Encryptor.digest(User, 'a11f-source-backup')]
      user.save!
      user.update_columns(
        created_at: @api_auth_now - 86_400, updated_at: @api_auth_now - 86_400,
        active_until: entry.fetch(:active_until, nil), deleted_at: entry[:deleted] ? @api_auth_now : nil,
        locked_at: entry[:locked] && !otp ? @api_auth_now : nil, failed_attempts: 7,
        failed_otp_attempts: entry.fetch(:attempts, 3),
        otp_locked_at: if entry[:locked] && otp
                         @api_auth_now - 60
                       else
                         (entry[:expired_lock] ? @api_auth_now - 1801 : nil)
                       end,
        consumed_timestep: entry[:consumed] ? @api_auth_now.to_i / 30 : nil
      )
      user.update_columns(otp_backup_codes: []) if entry[:no_backup]
      user.update_columns(provider: 'openid_connect', uid: 'a11f-synthetic-provider') if entry[:provider]
      user.update_columns(settings: { 'maps' => { 'url' => '  https://example.invalid  ' } }) if entry[:dirty]
      user
    end

    def api_auth_caller(entry)
      return unless entry[:caller] || entry[:family]

      id = 954_511
      email = 'a11f-source-caller@example.invalid'
      expect(User.unscoped.where('id = ? OR email = ?', id, email).exists?).to be(false)
      @api_auth_actors << [id, [email]]
      caller = create(:user, id: id, email: email, plan: :family, settings: { 'timezone' => 'Europe/Berlin' },
                            active_until: @api_auth_now + 86_400, skip_auto_trial: true, skip_family_sync: true)
      caller.update_columns(created_at: @api_auth_now - 86_400, updated_at: @api_auth_now - 86_400)
      if entry[:family]
        expect(Family.where(id: 954_512).exists?).to be(false)
        @api_auth_family = [954_512, caller.id]
        family = create(:family, id: 954_512, creator: caller)
        create(:family_membership, :owner, id: 954_513, family: family, user: caller)
        create(:family_membership, id: 954_514, family: family, user: User.find(954_510))
      end
      caller
    end

    def api_auth_http_row(entry, kind)
      @api_auth_index = (@api_auth_index || 0) + 1
      now = @api_auth_now
      totp = ROTP::TOTP.new('JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP')
      if entry[:code] == :leading
        epoch = (0..1000).map { |offset| now.to_i + offset * 30 }.find { |at| totp.at(at).start_with?('0') }
        now = Time.at(epoch).utc
      end
      travel_to(now) do
        reset!
        user = api_auth_actor(entry, otp: kind == :challenge)
        caller = api_auth_caller(entry)
        allow(DawarichSettings).to receive(:two_factor_available?).and_return(entry.fetch(:available, true))
        jti = format('51000000-0000-4000-8000-%012d', @api_auth_index)
        allow(SecureRandom).to receive(:uuid).and_return(jti)
        token = Auth::IssueOtpChallengeToken.new(user).call if kind == :challenge
        key = "otp_challenge:consumed:#{jti}"
        @api_auth_keys << key
        @api_auth_keys << "otp_lockout_email_throttle/user/#{user.id}"
        user.update_columns(otp_required_for_login: false) if entry[:changed_flag]
        user.update_columns(email: 'a11f-changed@example.invalid') if entry[:changed_identity]
        user.update!(password: 'a11f-source-changed-password') if entry[:changed_password]
        user.update!(otp_secret: ROTP::Base32.encode('a11f-source-replacement')) if entry[:changed_secret]
        code = case entry[:code]
               when :backup then 'a11f-source-backup'
               when :strip then "  #{totp.at(now)}  "
               when :whitespace then totp.at(now).insert(3, ' ')
               when :invalid then 'invalid'
               else totp.at(now + entry.fetch(:offset, 0))
               end
        params = if kind == :login
                   { email: entry.fetch(:email, user.email),
                     password: entry.fetch(:supplied, entry.fetch(:password, 'a11f-source-password')) }
                 else
                   { challenge_token: token, otp_code: code }
                 end
        content_type = entry[:format] == :form ? 'application/x-www-form-urlencoded' : 'application/json'
        headers = { 'Host' => 'localhost', 'Accept' => 'application/json', 'Content-Type' => content_type }
        case entry[:caller]
        when :bearer then headers['Authorization'] = "Bearer #{caller.api_key}"
        when :param then params[:api_key] = caller.api_key
        when :unknown then headers['Authorization'] = 'Bearer unknown'
        when :null then params[:api_key] = nil
        end
        headers['Accept-Language'] = entry[:locale] if entry[:locale]
        headers.merge!(entry.fetch(:headers, {}))
        target = kind == :login ? '/api/v1/auth/login' : '/api/v1/auth/otp_challenge'
        target += entry.fetch(:query, '')
        raw = entry.fetch(:raw) do
          entry[:format] == :form ? URI.encode_www_form(params) : JSON.generate(params)
        end
        clear_enqueued_jobs
        before = api_auth_state
        trace = []
        subscriber = lambda do |_name, _start, _finish, _id, payload|
          sql = payload[:sql]
          trace << (sql.include?('failed_otp_attempts') ? 'reset' : 'consume') if sql.start_with?('UPDATE "users"')
        end
        allow_any_instance_of(Auth::VerifyOtpChallengeToken).to receive(:mark_consumed!).and_wrap_original do |original|
          trace << 'mark'
          original.call
        end
        failure_target = api_auth_inject(entry[:failure])
        if entry[:replay]
          post target, params: raw, headers: headers
          expect(response.status).to eq(200)
          trace.clear
        end
        error = nil
        begin
          ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
            post target, params: raw, headers: headers
          end
        rescue StandardError => e
          error = e.class.name
        end
        if entry[:failure]
          expect(error).to eq('RuntimeError')
        elsif entry[:error]
          expect(error).to eq(entry[:error])
        else
          expect(error).to be_nil, entry[:name]
          expect(response.status).to eq(entry.fetch(:status, 200)), entry[:name]
        end
        metadata_caller = %i[bearer param].include?(entry[:caller]) ? caller : nil
        result = error ? { 'error_class' => error } : api_auth_response(user, metadata_caller)
        after = api_auth_state
        if kind == :login
          expect(after == before).to be(true), entry[:name]
        elsif !error && response.status == 200
          expect(trace).to eq(%w[consume mark reset])
          expect(user.reload.failed_otp_attempts).to eq(0)
        end
        replacements = { 'a11f-source-password' => 'runtime:password',
                         'a11f-source-backup' => 'runtime:backup_code', token => 'runtime:challenge_token',
                         user.api_key => 'runtime:api_key', caller&.api_key => 'runtime:caller_api_key' }.compact
        replacements[params[:password]] = 'runtime:password' if kind == :login && entry[:password]
        replacements[code] = "runtime:#{entry.fetch(:code, :totp)}" if kind == :challenge && entry[:code] != :invalid
        public_raw = replacements.reduce(raw.b) do |body, (value, marker)|
          value ? body.gsub(value.b, marker.b) : body
        end.force_encoding(Encoding::UTF_8)
        public_headers = headers.map do |name, value|
          [name, value.start_with?('Bearer ') && caller ? 'Bearer runtime:caller_api_key' : value]
        end
        { 'name' => entry[:name], 'source_time' => now.iso8601,
          'request' => { 'method' => 'POST', 'target' => target, 'headers' => public_headers, 'body' => public_raw },
          'response' => result, 'before' => before, 'after' => after, 'trace' => trace,
          'consumed' => Rails.cache.exist?(key), 'jobs' => enqueued_jobs.map { |job| job[:job].name } }
      ensure
        if failure_target
          target_class, method = failure_target
          allow_any_instance_of(target_class).to receive(method).and_call_original
        end
        api_auth_cleanup
      end
    end

    def api_auth_inject(failure)
      return unless failure

      target = case failure
               when :mark then [Auth::VerifyOtpChallengeToken, :mark_consumed!]
               when :reset then [User, :reset_failed_otp_attempts!]
               else [Api::V1::Auth::OtpChallengesController, :render_auth_success]
               end
      allow_any_instance_of(target.first).to receive(target.last).and_raise('a11f-source-partial-failure')
      target
    end

    def api_auth_response(user, caller)
      raw = response.body
      body = JSON.parse(raw) if response.media_type == 'application/json'
      headers = response.headers.to_h.transform_keys(&:downcase).except('date', 'content-length')
      headers.merge!(PlacesGoldenSupport::VOLATILE.slice(*headers.keys))
      if body&.key?('api_key')
        expect(body['api_key'] == user.api_key).to be(true)
        expect(body['user_id']).to eq(user.id)
        raw = raw.gsub(user.api_key, 'runtime:api_key')
      elsif body&.key?('challenge_token')
        claims, = JWT.decode(body['challenge_token'], Auth::InternalTokenSecret.call, true, algorithm: 'HS256')
        expect(claims['user_id']).to eq(user.id)
        expect(claims['purpose']).to eq('otp_challenge')
        expect(body['ttl']).to eq(300)
        raw = raw.gsub(body['challenge_token'], 'runtime:challenge_token')
      end
      if response.status < 400
        expect(response.headers['Set-Cookie']).to be_nil unless request.headers['X-Dawarich-Client']
        if [200, 201].include?(response.status)
          expect(headers['etag']).to match(%r{\AW/"[0-9a-f]{32}"\z})
          expect(headers['etag'] == "W/\"#{Digest::SHA256.hexdigest(response.body)[0, 32]}\"").to be(true)
          headers['etag'] = 'runtime:auth_response_etag'
        else
          expect(headers['etag']).to be_nil
          expect(headers['cache-control']).to eq('no-cache')
        end
      end
      expect(headers['x-dawarich-response']).to eq("Hey, I'm alive#{caller ? ' and authenticated' : ''}!")
      { 'status' => response.status, 'headers' => headers, 'body' => raw }
    end

    def api_auth_state
      fields = %w[id email api_key status plan subscription_source active_until encrypted_password
                  otp_secret otp_required_for_login otp_backup_codes consumed_timestep failed_otp_attempts
                  otp_locked_at failed_attempts locked_at remember_created_at sign_in_count current_sign_in_at
                  last_sign_in_at current_sign_in_ip last_sign_in_ip settings created_at updated_at deleted_at]
      ids = @api_auth_actors.map(&:first)
      return [] if ids.empty?

      connection = ActiveRecord::Base.connection
      sql = "SELECT row_to_json(t)::text FROM (SELECT #{fields.join(',')} FROM users " \
            "WHERE id IN (#{ids.join(',')}) ORDER BY id) t"
      connection.select_values(sql).map do |encoded|
        row = JSON.parse(encoded)
        row['api_key'] = row['id'] == 954_510 ? 'runtime:api_key' : 'runtime:caller_api_key'
        row['encrypted_password'] = 'runtime:password_digest'
        row['otp_secret'] = 'runtime:encrypted_otp_secret' if row['otp_secret']
        row['otp_backup_codes'] = row['otp_backup_codes']&.map { 'runtime:backup_code_digest' }
        row
      end
    end

    def api_auth_cleanup
      @api_auth_keys&.each { |key| Rails.cache.delete(key) }
      @api_auth_keys = []
      if @api_auth_family
        id, creator = @api_auth_family
        Family::Membership.where(id: [954_513, 954_514], family_id: id, user_id: [954_510, 954_511]).delete_all
        Family.where(id: id, creator_id: creator).delete_all
        @api_auth_family = nil
      end
      @api_auth_actors&.each { |id, emails| User.unscoped.where(id: id, email: emails).delete_all }
      @api_auth_actors = []
    end

    def api_auth_exclusion_cases
      normal = { email: 'a11f-source@example.invalid', password: 'a11f-source-password' }
      [
        { name: 'query', query: '?extra=1' }, { name: 'mobile-ios', headers: { 'X-Dawarich-Client' => 'ios' } },
        { name: 'mobile-android', headers: { 'X-Dawarich-Client' => 'android' } },
        { name: 'extra-json', raw: JSON.generate(normal.merge(extra: 'value')) },
        { name: 'duplicate-json', raw: JSON.generate(normal).sub('}', ',"email":"a11f-source@example.invalid"}') },
        { name: 'duplicate-form', format: :form,
          raw: "#{URI.encode_www_form(normal)}&email=a11f-source%40example.invalid" },
        { name: 'nested-json', raw: JSON.generate(normal.merge(email: { nested: 'value' })), status: 401 },
        { name: 'numeric-json', raw: JSON.generate(normal.merge(email: 123)), status: 401 },
        { name: 'root-array', raw: JSON.generate([normal]), status: 401 },
        { name: 'provider-local-password', provider: true },
        { name: 'dirty-settings', dirty: true }
      ]
    end

    def api_auth_cache_rows
      rows = []
      travel_to(@api_auth_now) do
        user = api_auth_actor({})
        jti = '52000000-0000-4000-8000-000000000001'
        allow(SecureRandom).to receive(:uuid).and_return(jti)
        token = Auth::IssueOtpChallengeToken.new(user).call
        key = "otp_challenge:consumed:#{jti}"
        @api_auth_keys << key
        [true, false, nil, :corrupt, :expired].each do |value|
          @api_auth_redis.del(key)
          case value
          when :corrupt then @api_auth_redis.set(key, 'a11f-corrupt-cache')
          when :expired
            entry = ActiveSupport::Cache::Entry.new(true, expires_at: @api_auth_now.to_f - 1)
            @api_auth_redis.set(key, Rails.cache.send(:serialize_entry, entry))
          else Rails.cache.write(key, value, expires_in: 300)
          end
          exists = Rails.cache.exist?(key)
          result = begin
            Auth::VerifyOtpChallengeToken.new(token).call
            'accepted'
          rescue Auth::VerifyOtpChallengeToken::InvalidToken => e
            e.class.name
          end
          expect(exists).to eq(!%i[corrupt expired].include?(value))
          rows << { 'name' => value.nil? ? 'nil' : value.to_s, 'value' => value.is_a?(Symbol) ? value.to_s : value,
                    'exists' => exists, 'verification' => result,
                    'wire_base64' => Base64.strict_encode64(@api_auth_redis.get(key)) }
        end
        @api_auth_redis.del(key)
        verifier = Auth::VerifyOtpChallengeToken.new(token)
        expect(verifier.call.id).to eq(user.id)
        travel_to(@api_auth_now + 299)
        expect(verifier.mark_consumed!).to be(true)
        raw = @api_auth_redis.get(key)
        ttl = @api_auth_redis.pttl(key)
        entry = Rails.cache.send(:deserialize_entry, raw)
        expect(ttl).to be_between(299_000, 300_000)
        expect(entry.expires_at).to eq((@api_auth_now + 599).to_f)
        expect(verifier.mark_consumed!).to be(false)
        expect(@api_auth_redis.get(key) == raw).to be(true)
        expect(@api_auth_redis.pttl(key)).to be_between(ttl - 1000, ttl)
        rows << { 'name' => 'late-consumption-nx', 'consumed_at' => (@api_auth_now + 299).iso8601,
                  'expires_at' => (@api_auth_now + 599).iso8601, 'ttl_ms' => 300_000,
                  'nx_retains_value_and_ttl' => true, 'wire_base64' => Base64.strict_encode64(raw) }
        travel_to(@api_auth_now)
        @api_auth_redis.del(key)
        allow(@api_auth_redis).to receive(:get).and_raise(Redis::CannotConnectError, 'a11f-read-down')
        read_result = Auth::VerifyOtpChallengeToken.new(token).call.id == user.id
        expect(read_result).to be(true)
        allow(@api_auth_redis).to receive(:get).and_call_original
        allow(@api_auth_redis).to receive(:set).and_raise(Redis::CannotConnectError, 'a11f-write-down')
        write_result = verifier.mark_consumed!
        expect(write_result).to be_nil
        allow(@api_auth_redis).to receive(:set).and_call_original
        rows << { 'name' => 'suppressed-redis-errors', 'read_error_accepts_actor' => read_result,
                  'write_result' => write_result }
      ensure
        api_auth_cleanup
      end
      rows
    end

    def api_auth_token_rows
      public_rows = []
      vectors = []
      contexts = [
        ['explicit', ApiJwtFixture.secret('jwt'), ApiJwtFixture.secret('fallback')],
        ['unset', nil, ApiJwtFixture.secret('fallback')],
        ['empty', '', ApiJwtFixture.secret('fallback')],
        ['blank', " \t\n", ApiJwtFixture.secret('fallback')],
        ['padded', "  #{ApiJwtFixture.secret('jwt')}  ", ApiJwtFixture.secret('fallback')],
        ['unavailable', nil, nil]
      ]
      travel_to(@api_auth_now) do
        user = api_auth_actor({})
        contexts.each_with_index do |(name, jwt_secret, fallback), index|
          allow(ENV).to receive(:[]).with('JWT_SECRET_KEY').and_return(jwt_secret)
          allow(Rails.application).to receive(:secret_key_base).and_return(fallback)
          jti = format('53000000-0000-4000-8000-%012d', index + 1)
          allow(SecureRandom).to receive(:uuid).and_return(jti)
          secret = Auth::InternalTokenSecret.call
          if name == 'unavailable'
            expect(secret).to be_nil
            expect { Auth::IssueOtpChallengeToken.new(user).call }.to raise_error(JWT::EncodeError)
            vectors << { 'name' => name, 'context' => { 'jwt_secret_key' => jwt_secret,
                         'auth_jwt_secret_key' => ApiJwtFixture.secret('mobile'), 'rails_secret' => fallback },
                         'expected' => 'unavailable', 'user_id' => user.id, 'now' => @api_auth_now.to_i, 'jti' => jti }
            public_rows << { 'name' => name, 'expected' => 'unavailable' }
            next
          end
          token = Auth::IssueOtpChallengeToken.new(user).call
          claims, header = JWT.decode(token, secret, true, algorithm: 'HS256')
          expect(claims.keys).to eq(%w[user_id purpose jti iat exp])
          expect(Auth::VerifyOtpChallengeToken.new(token).call.id).to eq(user.id)
          expect { JWT.decode(token, ApiJwtFixture.secret('mobile'), true, algorithm: 'HS256') }
            .to raise_error(JWT::VerificationError)
          vectors << { 'name' => name, 'source' => 'issuer', 'token' => token,
                       'context' => { 'jwt_secret_key' => jwt_secret,
                                      'auth_jwt_secret_key' => ApiJwtFixture.secret('mobile'),
                                      'rails_secret' => fallback },
                       'secret' => secret, 'user_id' => user.id, 'now' => @api_auth_now.to_i,
                       'jti' => jti, 'claims' => claims, 'expected' => 'accepted' }
          public_rows << { 'name' => name, 'header' => header, 'claims' => claims.merge('jti' => 'runtime:jti'),
                           'signature_verified' => true, 'mobile_secret_rejected' => true, 'expected' => 'accepted' }
        end
        allow(ENV).to receive(:[]).with('JWT_SECRET_KEY').and_return(ApiJwtFixture.secret('jwt'))
        allow(Rails.application).to receive(:secret_key_base).and_return(ApiJwtFixture.secret('fallback'))
        jti = '53000000-0000-4000-8000-000000000010'
        allow(SecureRandom).to receive(:uuid).and_return(jti)
        normal = Auth::IssueOtpChallengeToken.new(user).call
        claims, = JWT.decode(normal, Auth::InternalTokenSecret.call, true, algorithm: 'HS256')
        boundaries = [
          ['age300', { 'iat' => @api_auth_now.to_i - 300, 'exp' => @api_auth_now.to_i + 1 }, 'accepted'],
          ['age301', { 'iat' => @api_auth_now.to_i - 301, 'exp' => @api_auth_now.to_i + 1 }, 'invalid'],
          ['future-iat', { 'iat' => @api_auth_now.to_i + 60 }, 'accepted'],
          ['expiry-equal', { 'exp' => @api_auth_now.to_i }, 'invalid'],
          ['expiry-before', { 'exp' => @api_auth_now.to_i - 1 }, 'invalid'],
          ['missing-iat', { 'iat' => nil }, 'accepted'], ['missing-exp', { 'exp' => nil }, 'accepted'],
          ['wrong-purpose', { 'purpose' => 'trial_welcome' }, 'invalid'],
          ['blank-jti', { 'jti' => '  ' }, 'invalid'], ['non-uuid', { 'jti' => 'a11f-non-uuid' }, 'accepted'],
          ['extra', { 'extra' => true }, 'accepted'],
          ['future-nbf', { 'nbf' => @api_auth_now.to_i + 1 }, 'invalid'],
          ['past-nbf', { 'nbf' => @api_auth_now.to_i - 1 }, 'accepted'],
          ['string-id', { 'user_id' => user.id.to_s }, 'accepted'],
          ['string-iat', { 'iat' => @api_auth_now.to_i.to_s }, 'accepted'],
          ['float-iat', { 'iat' => @api_auth_now.to_i + 0.5 }, 'accepted'],
          ['missing-actor', { 'user_id' => -1 }, 'invalid']
        ]
        boundaries.each do |name, changes, expected|
          payload = claims.merge(changes).reject { |_key, value| value.nil? }
          token = if name == 'string-iat'
                    input = [{ 'alg' => 'HS256' }, payload].map do |part|
                      Base64.urlsafe_encode64(JSON.generate(part), padding: false)
                    end.join('.')
                    digest = OpenSSL::HMAC.digest('SHA256', Auth::InternalTokenSecret.call, input)
                    "#{input}.#{Base64.urlsafe_encode64(digest, padding: false)}"
                  else
                    JWT.encode(payload, Auth::InternalTokenSecret.call, 'HS256')
                  end
          result = api_auth_verification(token)
          expect(result).to eq(expected), name
          vectors << { 'name' => name, 'source' => 'parser', 'token' => token,
                       'secret' => Auth::InternalTokenSecret.call, 'claims' => payload,
                       'now' => @api_auth_now.to_i, 'expected' => result }
          public_rows << { 'name' => name, 'claims' => payload.merge('jti' => 'runtime:jti'), 'expected' => result }
        end
        %w[HS384 HS512 none].each do |algorithm|
          token = JWT.encode(claims, Auth::InternalTokenSecret.call, algorithm)
          expect(api_auth_verification(token)).to eq('invalid')
          vectors << { 'name' => algorithm, 'source' => 'parser', 'token' => token,
                       'secret' => Auth::InternalTokenSecret.call, 'now' => @api_auth_now.to_i,
                       'expected' => 'invalid' }
          public_rows << { 'name' => algorithm, 'expected' => 'invalid' }
        end
        segments = normal.split('.')
        segments.last[0] = segments.last.start_with?('a') ? 'b' : 'a'
        special = [
          ['tampered', segments.join('.'), 'invalid'], ['nil-token', nil, 'invalid'],
          ['blank-token', '', 'invalid'], ['malformed', 'malformed', 'invalid'],
          ['wrong-secret', JWT.encode(claims, ApiJwtFixture.secret('wrong'), 'HS256'), 'invalid'],
          ['extra-header', JWT.encode(claims, Auth::InternalTokenSecret.call, 'HS256', { 'typ' => 'JWT' }), 'accepted']
        ]
        special.each do |name, token, expected|
          expect(api_auth_verification(token)).to eq(expected)
          vectors << { 'name' => name, 'source' => 'parser', 'token' => token,
                       'secret' => Auth::InternalTokenSecret.call, 'now' => @api_auth_now.to_i, 'expected' => expected }
          public_rows << { 'name' => name, 'expected' => expected }
        end
        user.update_columns(deleted_at: @api_auth_now)
        expect(api_auth_verification(normal)).to eq('invalid')
        public_rows << { 'name' => 'deleted-actor', 'expected' => 'invalid' }
      ensure
        api_auth_cleanup
      end
      [public_rows, { 'vectors' => vectors }]
    end

    def api_auth_verification(token)
      Auth::VerifyOtpChallengeToken.new(token).call
      'accepted'
    rescue Auth::VerifyOtpChallengeToken::InvalidToken
      'invalid'
    end

    def api_auth_race_row(kind)
      travel_to(@api_auth_now) do
        user = api_auth_actor({}, otp: true)
        jti = kind == :totp ? '54000000-0000-4000-8000-000000000001' : '54000000-0000-4000-8000-000000000002'
        allow(SecureRandom).to receive(:uuid).and_return(jti)
        token = Auth::IssueOtpChallengeToken.new(user).call
        @api_auth_keys << "otp_challenge:consumed:#{jti}"
        before = api_auth_state
        code = kind == :totp ? user.current_otp : 'a11f-source-backup'
        ready = Queue.new
        release = [Queue.new, Queue.new]
        marks = []
        pool = ActiveRecord::Base.connection_pool
        observer = pool.checkout
        allow_any_instance_of(User).to receive(:validate_and_consume_otp!).and_wrap_original do |original, value|
          index = Thread.current[:a11f_generator_worker]
          unless index.nil?
            connection = ActiveRecord::Base.connection
            ready << [connection.select_value('SELECT pg_backend_pid()'), original.receiver.consumed_timestep]
            release[index].pop
          end
          original.call(value)
        end
        allow_any_instance_of(Auth::VerifyOtpChallengeToken).to receive(:mark_consumed!).and_wrap_original do |original|
          result = original.call
          marks << [Thread.current[:a11f_generator_worker], result]
          result
        end
        workers = [0, 1].map do |index|
          Thread.new do
            Thread.current[:a11f_generator_worker] = index
            pool.with_connection do
              client = ActionDispatch::Integration::Session.new(Rails.application)
              client.post('/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: code }, as: :json)
              { 'status' => client.response.status,
                'subject_matches' => JSON.parse(client.response.body)['user_id'] == user.id,
                'cookie' => client.response.headers['Set-Cookie'].present? }
            end
          end
        end
        prepared = Timeout.timeout(5) { [ready.pop, ready.pop] }
        expect(prepared.map(&:first).uniq.size).to eq(2)
        expect(prepared.map(&:first)).not_to include(observer.select_value('SELECT pg_backend_pid()'))
        expect(prepared.map(&:last)).to eq([nil, nil])
        outcomes = workers.each_index.map do |index|
          release[index] << true
          workers[index].value
        end
        expect(outcomes.map { |outcome| outcome['status'] }).to eq([200, 200])
        expect(marks).to eq([[0, true], [1, false]])
        observed = observer.select_one("SELECT failed_otp_attempts, consumed_timestep FROM users WHERE id=#{user.id}")
        expect(observed['failed_otp_attempts']).to eq(0)
        expect(observed['consumed_timestep']).to eq(kind == :totp ? @api_auth_now.to_i / 30 : nil)
        { 'name' => "#{kind}-prepared-overlap", 'backends_distinct' => true, 'outcomes' => outcomes,
          'marks' => marks, 'before' => before, 'after' => api_auth_state,
          'consumed' => Rails.cache.exist?(@api_auth_keys.last) }
      ensure
        release&.each { |queue| queue << true }
        workers&.each(&:join)
        pool.checkin(observer) if observer
        allow_any_instance_of(User).to receive(:validate_and_consume_otp!).and_call_original
        api_auth_cleanup
      end
    end
  end

  it 'records account responses and database effects from Rails' do
    oracle = ApiAccountGoldenOracle
    cases = places_cases(oracle).map do |entry|
      kase = { method: :get, auth: :bearer, expect: :own, env: {}, content: oracle::JSON_TYPE }.merge(entry)
      result = places_record(kase, oracle:, strict: true)
      status = result.dig('response', 'status')
      expect(status).to eq(entry.fetch(:status, 200)), "#{entry[:name]}: HTTP#{status}"
      payload = result.dig('response', 'body').presence
      json = result.dig('response', 'headers', 'content-type').to_s.start_with?('application/json')
      payload = payload && json ? JSON.parse(payload) : nil
      expect(payload['error']).to eq(entry[:error]), entry[:name] if entry[:error]
      expect(payload).to eq(entry[:json]), entry[:name] if entry[:json]
      if entry[:me]
        expect(payload.dig('user', 'id')).to eq(oracle::OWNER)
        expect(payload.dig('user', 'settings', 'timezone')).to eq(entry.dig(:user, :timezone) || 'UTC')
        expect(payload.dig('features', 'reverse_geocoding')).to eq(entry.fetch(:geocoding, false))
        expect(payload.dig('user', 'settings', 'maps')).to be_a(Hash)
      end
      before = oracle.setups.fetch(result.fetch('setup')).to_h
      after = result.fetch('after')
      owner = after.fetch('users').find { _1['id'] == oracle::OWNER }
      prior = before.fetch('users').find { _1['id'] == oracle::OWNER }
      if entry[:path].start_with?(oracle::T)
        fields = %w[consumed_timestep failed_otp_attempts otp_locked_at]
        expect(owner.keys).to include(*fields)
        expect(owner.values_at('failed_otp_attempts', 'otp_locked_at')).to eq(
          prior.values_at('failed_otp_attempts', 'otp_locked_at')
        )
        if entry[:disabled] || entry[:second_save_failure]
          expected = entry[:code] == :current ? oracle::NOW.to_i / 30 : prior['consumed_timestep']
          expect(owner['consumed_timestep']).to eq(expected)
        else
          expect(owner['consumed_timestep']).to eq(prior['consumed_timestep'])
        end
        if entry[:crypto] == :backup
          expect(owner.values_at('otp_secret', 'otp_required_for_login')).to eq(
            prior.values_at('otp_secret', 'otp_required_for_login')
          )
        end
        if entry[:second_save_failure]
          expect(owner.values_at('otp_secret', 'otp_required_for_login', 'otp_backup_codes')).to eq(
            prior.values_at('otp_secret', 'otp_required_for_login', 'otp_backup_codes')
          )
          expect(payload).to eq('status' => 422, 'error' => 'Unprocessable Content')
        end
      end
      expect(owner['deleted_at']).to eq('2026-10-03T12:00:00') if entry[:deleted]
      if entry[:disabled]
        expect(owner.values_at('otp_secret', 'otp_required_for_login', 'otp_backup_codes')).to eq([nil, false, []])
      end
      if entry[:cloud_delete]
        expect(owner['deleted_at']).to be_nil
        expect(result.fetch('cache_after').values.first['value']).to be(true)
      end
      untouched = kase[:method] == :get || (status >= 400 && !entry[:deleted] && !entry[:second_save_failure])
      expect(after).to eq(before), entry[:name] if untouched
      result['jobs_after'] = account_jobs
      expect(result['jobs_after'].length).to eq(entry[:jobs]), entry[:name] if entry[:jobs]
      account_crypto(result, payload, entry, owner) if entry[:crypto]
      account_runtime_request(result, entry)
      expect(result.fetch('ignore')).to eq([])
      expect(result).not_to have_key('mask')
      result
    end
    path = Rails.root.join(ENV.fetch('API_GOLDEN_OUTPUT', 'app-phoenix/test/fixtures/api_account/golden.json'))
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'now' => oracle::NOW.iso8601,
                'runtime_seed_fields' => %w[users.encrypted_password users.otp_secret users.otp_backup_codes],
                'sequences' => oracle::SEQUENCES, 'setups' => oracle.setups.sort.to_h,
                'cases' => cases.sort_by { _1['name'] } }
    encoded = "#{Oj.dump(fixture, mode: :strict, indent: 2, float_precision: 0).rstrip}\n"
    if ENV['WRITE_PHOENIX_FIXTURES'] == '1'
      FileUtils.mkdir_p(path.dirname)
      File.write(path, encoded)
    else
      expect(path.read == encoded).to be(true), 'account golden fixture differs from Rails'
    end
  end

  def places_seed(kase)
    oracle = ApiAccountGoldenOracle
    reset!
    clear_enqueued_jobs
    Rails.cache.clear
    FixtureCleanup.delete!(%w[users families family_memberships instance_settings])
    InstanceSettings::Resolver.reset!
    allow(DawarichSettings).to receive(:self_hosted?).and_return(true)
    allow(DawarichSettings).to receive(:two_factor_available?).and_return(kase.fetch(:available, true))
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SUBSCRIPTION_WEBHOOK_SECRET').and_return(
      kase[:webhook] == :missing ? nil : oracle::WEBHOOK
    )
    stamps = { created_at: oracle::STAMP, updated_at: oracle::STAMP }
    user = { status: 1, timezone: 'UTC' }.merge(kase[:user] || {})
    password = BCrypt::Password.create(oracle::PASSWORD, cost: 4).to_s
    places_insert('users', id: oracle::OWNER, email: 'a4rest-account@example.invalid', api_key: oracle::KEY,
                           status: user[:status], settings: user[:settings] || { 'timezone' => user[:timezone] },
                           encrypted_password: password, deleted_at: user[:deleted_at],
                           provider: kase[:seed] == :oauth ? 'openid_connect' : nil,
                           uid: kase[:seed] == :oauth ? 'synthetic-oidc' : nil,
                           visits_redetected_at: oracle::STAMP, **stamps)
    places_insert('users', id: oracle::OTHER, email: 'a4rest-other@example.invalid', api_key: 'a4rest-account-other',
                           status: 1, settings: { 'timezone' => 'UTC' }, visits_redetected_at: oracle::STAMP, **stamps)
    account_family(kase, stamps) if %i[family single_family].include?(kase[:seed])
    if kase[:geocoding]
      places_insert('instance_settings', id: 954_901, key: 'photon_api_host',
                                         value: JSON.generate('photon.test.example.com'), **stamps)
      InstanceSettings::Resolver.reset!
    end
    @runtime_secret = nil
    @runtime_backup = nil
    @runtime_hashes = nil
    @first_codes = nil
    if kase[:otp]
      owner = User.find(oracle::OWNER)
      owner.otp_secret = User.generate_otp_secret
      owner.otp_required_for_login = kase[:otp] == :enabled
      owner.consumed_timestep = oracle::NOW.to_i / 30 if kase[:consumed]
      owner.failed_otp_attempts = 3
      owner.otp_locked_at = oracle::NOW - 60
      @runtime_backup = owner.generate_otp_backup_codes!.first if kase[:otp] == :enabled || kase[:backups]
      owner.save!
      @runtime_secret = owner.otp_secret
      @runtime_hashes = owner.otp_backup_codes
    end
    @runtime_body = (kase[:body] || {}).dup
    @runtime_body[:password] = kase[:password] == :valid ? oracle::PASSWORD : 'wrong' if kase[:password]
    if kase[:code]
      @runtime_body[:otp_code] = case kase[:code]
                                 when :current
                                   ROTP::TOTP.new(@runtime_secret).at(oracle::NOW + kase.fetch(:code_offset, 0))
                                 when :backup then @runtime_backup
                                 else 'invalid'
                                 end
    end
    kase[:body] = @runtime_body if @runtime_body.any?
    kase[:headers] = { 'X-Webhook-Secret' => oracle::WEBHOOK } if kase[:manager]
    kase[:cache_keys] = ["account_destroy:rate_limit:#{oracle::OWNER}"] if kase[:cloud_delete]
    if kase[:path] == oracle::EXIST
      kase[:env] = kase[:env].merge('SUBSCRIPTION_WEBHOOK_SECRET' =>
        (kase[:webhook] == :missing ? nil : 'runtime:webhook_secret'))
    end
    clear_enqueued_jobs
  end

  def account_family(kase, stamps)
    oracle = ApiAccountGoldenOracle
    places_insert('families', id: 954_101, creator_id: oracle::OWNER, name: 'Synthetic family', **stamps)
    places_insert('family_memberships', id: 954_201, family_id: 954_101, user_id: oracle::OWNER, role: 0, **stamps)
    return if kase[:seed] == :single_family

    places_insert('family_memberships', id: 954_202, family_id: 954_101, user_id: oracle::OTHER, role: 1, **stamps)
  end

  def places_rows(tables, strict: false)
    rows = super
    rows.fetch('users', []).each do |row|
      if row['encrypted_password'].present?
        expect(row['encrypted_password']).to match(/\A\$2[aby]\$04\$/)
        row['encrypted_password'] = 'runtime:password_digest'
      end
      if row['otp_secret'].present?
        expect(JSON.parse(row['otp_secret']).keys.sort).to eq(%w[h p])
        expect(User.find(row['id']).otp_secret).to match(/\A[A-Z2-7]{32}\z/)
        row['otp_secret'] = 'runtime:encrypted_otp_secret'
      end
      codes = row['otp_backup_codes']
      expect(codes.all? { _1.match?(%r{\A\$2[aby]\$04\$[./A-Za-z0-9]{53}\z}) }).to be(true) if codes
      row['otp_backup_codes'] = codes.map { 'runtime:backup_code_digest' } if codes
    end
    rows
  end

  def places_response(kase, target, headers, body, strict: false)
    if kase[:second_save_failure]
      config = Rails.application.env_config
      detailed = config['action_dispatch.show_detailed_exceptions']
      config['action_dispatch.show_detailed_exceptions'] = false
      allow_any_instance_of(User).to receive(:update!).and_wrap_original do |original, changes|
        original.receiver.email = nil
        original.call(changes)
      end
    end
    travel_to(ApiAccountGoldenOracle::NOW + kase[:source_offset]) if kase[:source_offset]
    if kase[:repeat]
      first = super
      @first_codes = JSON.parse(first['body'])['backup_codes'] if kase[:crypto] == :confirm
    end
    super
  ensure
    travel_to(ApiAccountGoldenOracle::NOW) if kase[:source_offset]
    if kase[:second_save_failure]
      config['action_dispatch.show_detailed_exceptions'] = detailed
      allow_any_instance_of(User).to receive(:update!).and_call_original
    end
  end

  def account_crypto(result, payload, entry, owner)
    user = User.find(ApiAccountGoldenOracle::OWNER)
    raw = result['response']['body']
    if entry[:crypto] == :setup
      expect(payload.keys).to eq(%w[provisioning_uri secret])
      expect(payload['secret'].match?(/\A[A-Z2-7]{32}\z/)).to be(true)
      expect(user.otp_secret == payload['secret']).to be(true)
      expect(payload['secret'] != @runtime_secret).to be(true) if @runtime_secret
      expect(payload['provisioning_uri'].include?("secret=#{payload['secret']}")).to be(true)
      expect(payload['provisioning_uri'].include?('issuer=Dawarich')).to be(true)
      expect(user.otp_required_for_login).to be(false)
      raw = raw.gsub(payload['secret'], 'runtime:otp_secret')
      payload['provisioning_uri'] = payload['provisioning_uri'].sub(payload['secret'], 'runtime:otp_secret')
      payload['secret'] = 'runtime:otp_secret'
    else
      codes = payload.fetch('backup_codes')
      expect(codes.length).to eq(10)
      expect(codes.uniq.length).to eq(10)
      expect(codes.all? { _1.match?(/\A[0-9a-f]{24}\z/) }).to be(true)
      expect(user.otp_backup_codes.uniq.length).to eq(10)
      expect(user.otp_backup_codes).not_to eq(@runtime_hashes)
      expect(codes).not_to eq(@first_codes) if @first_codes
      compatible = codes.zip(user.otp_backup_codes).all? { |code, hash| Devise::Encryptor.compare(User, hash, code) }
      expect(compatible).to be(true)
      expect(user.invalidate_otp_backup_code!(@runtime_backup)).to be(false) if @runtime_backup
      expect(user.invalidate_otp_backup_code!(codes.first)).to be(true)
      expect(user.invalidate_otp_backup_code!(codes.first)).to be(false)
      expect(owner['otp_backup_codes'].length).to eq(10)
      expect(owner['otp_required_for_login']).to be(true) if entry[:crypto] == :confirm
      codes.each { raw = raw.gsub(_1, 'runtime:backup_code') }
      payload['backup_codes'] = Array.new(10, 'runtime:backup_code')
    end
    result['response']['body'] = raw
    etag = result['response']['headers'].fetch('etag')
    expect(etag).to match(%r{\AW/"[0-9a-f]{32,64}"\z})
    result['response']['headers']['etag'] = 'runtime:crypto_response_etag'
    result['runtime_crypto'] = entry[:crypto].to_s
  end

  def account_jobs
    enqueued_jobs.map do |job|
      args = Marshal.load(Marshal.dump(job[:args]))
      if job[:job] == Users::MailerSendingJob
        url = args.last.fetch('link_url')
        token = Rack::Utils.parse_query(URI.parse(url).query).fetch('token')
        travel_to(ApiAccountGoldenOracle::NOW) do
          expect(Users::VerifyDestroyToken.new(token).call.user.id).to eq(ApiAccountGoldenOracle::OWNER)
        end
        args.last['link_url'] = url.sub(token, 'runtime:destroy_token')
      end
      { 'job' => job[:job].name, 'args' => args }
    end
  end

  def account_runtime_request(result, entry)
    body = JSON.parse(result['request']['body'].presence || '{}')
    body['password'] = 'runtime:password' if entry[:password] == :valid
    body['otp_code'] = "runtime:#{entry[:code]}" if %i[current backup].include?(entry[:code])
    if entry[:password] == :valid || %i[current backup].include?(entry[:code])
      result['request']['body'] = JSON.generate(body)
      result['request']['headers'].reject! { _1[0] == 'Content-Length' }
      result['runtime_request'] = { 'password' => entry[:password]&.to_s, 'otp_code' => entry[:code]&.to_s }
      result['runtime_request']['otp_code_at'] = (ApiAccountGoldenOracle::NOW + entry.fetch(:code_offset, 0)).iso8601
    end
    result['source_time'] = (ApiAccountGoldenOracle::NOW + entry.fetch(:source_offset, 0)).iso8601
    return unless entry[:manager]

    result['request']['headers'].each { _1[1] = 'runtime:webhook_secret' if _1[0] == 'X-Webhook-Secret' }
    result['runtime_manager_secret'] = true
  end
end
