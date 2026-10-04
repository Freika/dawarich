# frozen_string_literal: true

require 'rails_helper'
require_relative 'places_golden_support'

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
    FileUtils.mkdir_p(path.dirname)
    fixture = { 'time_zone' => ENV.fetch('TIME_ZONE', nil), 'now' => oracle::NOW.iso8601,
                'runtime_seed_fields' => %w[users.encrypted_password users.otp_secret users.otp_backup_codes],
                'sequences' => oracle::SEQUENCES, 'setups' => oracle.setups.sort.to_h,
                'cases' => cases.sort_by { _1['name'] } }
    File.write(path, "#{Oj.dump(fixture, mode: :strict, indent: 2, float_precision: 0).rstrip}\n")
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
