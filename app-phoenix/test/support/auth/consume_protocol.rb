# frozen_string_literal: true

require 'json'
require 'time'
require 'stringio'
require 'uri'
require 'active_support/testing/time_helpers'

mode = ARGV[1]
fixture = JSON.parse(File.read(ARGV.fetch(0)))
database_allowed = if %w[api_auth api_auth_password_work api_auth_otp_work].include?(mode)
                     ENV.fetch('DATABASE_NAME') == fixture.fetch('database') &&
                       ENV.fetch('DATABASE_NAME').match?(/\Adawarich_(?:phoenix_)?test_/) &&
                       ENV.fetch('DATABASE_HOST') == '127.0.0.1'
                   else
                     ENV.fetch('DATABASE_NAME').start_with?('dawarich_test')
                   end
raise 'Protocol own test DB required' unless Rails.env.test? && database_allowed

ActiveJob::Base.queue_adapter = :test
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = false
raise 'Protocol fixture mode must match dispatch' unless fixture.fetch('mode', nil) == mode

Rails.application.reload_routes!
rack_env = {
  'REQUEST_METHOD' => 'GET', 'PATH_INFO' => '/', 'HTTP_HOST' => 'www.example.com',
  'SERVER_NAME' => 'www.example.com', 'SERVER_PORT' => '80',
  'rack.url_scheme' => 'http', 'rack.input' => StringIO.new
}
request = ActionDispatch::Request.new(Rails.application.env_config.merge(rack_env))

def jar(request, name, cookie)
  ActionDispatch::Cookies::CookieJar.build(request, name => URI.decode_www_form_component(cookie))
end

def native_client(cookies)
  ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
    session.host!('www.example.com')
    cookies.each { |name, value| session.cookies[name] = URI.decode_www_form_component(value) }
  end
end

def account_link_assert(label, condition, detail)
  raise "#{label}: #{detail}" unless condition
end

def account_link_state(user)
  user.reload.attributes.slice('provider', 'uid', 'sign_in_count', 'failed_attempts', 'failed_otp_attempts',
                               'otp_required_for_login', 'consumed_timestep', 'remember_created_at',
                               'current_sign_in_at', 'last_sign_in_at', 'current_sign_in_ip', 'last_sign_in_ip')
end

def account_link_submit(client, token, password = 'safepassword12', headers = {})
  params = { password: }
  params[:authenticity_token] = token unless token.nil?
  client.post('/auth/account_link/challenge', params:, headers:)
end

def account_link_session(client)
  jar(ActionDispatch::Request.new(Rails.application.env_config.dup), '_dawarich_session',
      URI.encode_www_form_component(client.cookies['_dawarich_session'])).encrypted['_dawarich_session']
end

def account_link_reset(user)
  user.update_columns(provider: nil, uid: nil, sign_in_count: 0, failed_attempts: 2,
                      current_sign_in_at: nil, last_sign_in_at: nil, current_sign_in_ip: nil, last_sign_in_ip: nil)
end

def account_link_source_pair(user, uid)
  auth = OmniAuth::AuthHash.new(provider: 'openid_connect', uid:,
                                info: { email: user.email, name: 'Synthetic' },
                                extra: { raw_info: { email_verified: true } })
  OmniAuth.config.mock_auth[:openid_connect] = auth
  Rails.application.env_config['omniauth.auth'] = auth
  client = native_client({})
  client.get('/users/auth/openid_connect/callback')
  raise 'A11e actual source callback refused' unless client.response.status == 302

  client.get('/auth/account_link/challenge')
  raise 'A11e actual source challenge refused' unless client.response.status == 200

  token = Nokogiri::HTML5(client.response.body)
                  .at_css("form[action='/auth/account_link/challenge'] input[name=authenticity_token]")['value']
  [URI.encode_www_form_component(client.cookies['_dawarich_session']), token, account_link_session(client)]
end

def account_link_overlap(user, cookie, token, label, baseline)
  previous_enabled = Rack::Attack.enabled
  previous_store = Rack::Attack.cache.store
  Rack::Attack.enabled = true
  Rack::Attack.cache.store = RackAttack::PhoenixCounterStore.new
  account_link_assert(label, Rack::Attack.enabled && Rack::Attack.cache.store.is_a?(RackAttack::PhoenixCounterStore),
                      'overlap shared counter store inactive')
  connection = ActiveRecord::Base.connection
  keys = ["rack::attack:#{Time.current.to_i / 900}:auth/account_link_challenge_session:#{user.id}",
          "rack::attack:#{Time.current.to_i / 900}:auth/account_link_challenge_ip:127.0.0.1"]
  owned = []
  keys.zip([baseline, 0]).each do |key, value|
    count = connection.select_value(User.sanitize_sql_array(['SELECT value FROM phoenix.counters WHERE key=?', key]))
    account_link_assert(label, value.zero? ? count.nil? : count == value, 'overlap counter baseline changed')
    owned << [key, value]
  end
  source_session = account_link_session(native_client('_dawarich_session' => cookie))
  before = account_link_state(user)
  ready = Queue.new
  release = [Queue.new, Queue.new]
  hook = Module.new do
    define_method(:valid_password?) do |value|
      result = super(value)
      index = Thread.current[:a11e_protocol_worker]
      unless index.nil?
        connection = ActiveRecord::Base.connection
        ready << [index, connection.select_value('SELECT pg_backend_pid()'),
                  User.where(id: id).exists?, result]
        release[index].pop
      end
      result
    end
  end
  User.prepend(hook)
  observer = ActiveRecord::Base.connection_pool.checkout
  workers = 2.times.map do |index|
    Thread.new do
      Thread.current[:a11e_protocol_worker] = index
      ActiveRecord::Base.connection_pool.with_connection do
        client = native_client('_dawarich_session' => cookie)
        account_link_submit(client, token)
        [client.response.status, account_link_session(client)]
      end
    end
  end
  prepared = Timeout.timeout(5) { [ready.pop, ready.pop] }
  account_link_assert(label, prepared.map { |row| row[1] }.uniq.size == 2, 'overlap connections not distinct')
  account_link_assert(label, prepared.all? do |row|
    row[2] && row[3]
  end, 'overlap actor not committed or password refused')
  account_link_assert(label, !prepared.map { |row| row[1] }.include?(observer.select_value('SELECT pg_backend_pid()')),
                      'overlap observer reused worker')
  outcomes = workers.each_index.map do |index|
    release[index] << true
    workers[index].value
  end
  account_link_assert(label, outcomes.map(&:first) == [302, 302], 'overlap statuses changed')
  outcomes.each do |outcome|
    session = outcome.last
    account_link_assert(label, session['warden.user.user.key'] == [[user.id], user.authenticatable_salt],
                        'overlap authentication changed')
    account_link_assert(label, (session.keys & %w[pending_oauth_link pending_oauth_link_attempts]).empty? &&
      session.keys.none? { |key| key.start_with?('devise.') }, 'overlap pending cleanup changed')
    account_link_assert(label, session['session_id'] != source_session['session_id'] &&
      session.slice('_csrf_token', 'user_return_to', 'locale') ==
        source_session.slice('_csrf_token', 'user_return_to', 'locale'), 'overlap session projection changed')
  end
  observed = observer.select_one(User.sanitize_sql_array(['SELECT * FROM users WHERE id=?', user.id]))
  account_link_assert(label, observed['sign_in_count'] == 1 && observed['failed_attempts'].zero? &&
    observed['failed_otp_attempts'] == before['failed_otp_attempts'] && observed['provider'] == 'openid_connect',
                      'overlap durable callback state changed')
  keys.zip([baseline + 2, 2]).each do |key, value|
    count = observer.select_value(User.sanitize_sql_array(['SELECT value FROM phoenix.counters WHERE key=?', key]))
    account_link_assert(label, count == value, 'overlap shared count changed')
  end
  puts 'Rails account-link overlap: PASS independent HTTP connections, session projections, ' \
       'durable callbacks and shared counts'
ensure
  release&.each { |queue| queue << true }
  workers&.each(&:join)
  ActiveRecord::Base.connection_pool.checkin(observer) if observer
  Rack::Attack.enabled = previous_enabled
  Rack::Attack.cache.store = previous_store
  owned&.each do |key, value|
    sql = if value.zero?
            ['DELETE FROM phoenix.counters WHERE key=?', key]
          else
            ['UPDATE phoenix.counters SET value=? WHERE key=?', value, key]
          end
    ActiveRecord::Base.connection.execute(User.sanitize_sql_array(sql))
  end
  hook&.send(:remove_method, :valid_password?)
end

def account_link_csrf(fixture, user, cookie, token)
  label = 'Rails account-link CSRF negatives preserve identity and authentication state'
  account_link_reset(user)
  before = account_link_state(user)
  cases = [[nil, {}], [fixture.fetch('foreign_token'), {}], [fixture.fetch('wrong_action_token'), {}],
           [token, { 'HTTP_ORIGIN' => 'https://foreign.invalid' }]]
  cases.each do |submitted, headers|
    client = native_client('_dawarich_session' => cookie)
    account_link_submit(client, submitted, 'safepassword12', headers)
    account_link_assert(label, client.response.status == 422, 'CSRF negative status changed')
    account_link_assert(label, account_link_state(user) == before, 'CSRF negative changed actor')
    account_link_assert(label, !account_link_session(client).key?('warden.user.user.key'),
                        'CSRF negative authenticated')
  end
  client = native_client('_dawarich_session' => cookie)
  account_link_submit(client, token)
  account_link_assert(label, client.response.status == 302 && user.reload.sign_in_count == 1,
                      'positive control refused')
  puts "#{label}: PASS missing, foreign-session, wrong-action, foreign Origin and valid control"
end

def account_link_rates(fixture, user, cookie, token)
  label = 'Rails account-link protocol enforces shared session and IP limits'
  account_link_assert(label, fixture.fetch('database') == ENV.fetch('DATABASE_NAME'), 'counter databases differ')
  previous_enabled = Rack::Attack.enabled
  previous_store = Rack::Attack.cache.store
  owned = fixture.fetch('counter_keys').dup
  Rack::Attack.enabled = true
  Rack::Attack.cache.store = RackAttack::PhoenixCounterStore.new
  account_link_assert(label, Rack::Attack.enabled && Rack::Attack.cache.store.is_a?(RackAttack::PhoenixCounterStore),
                      'shared store not enabled')
  connection = ActiveRecord::Base.connection
  values = owned.map do |key|
    sql = 'SELECT value,extract(epoch from expires_at-statement_timestamp()) AS ttl ' \
          'FROM phoenix.counters WHERE key=?'
    connection.select_one(User.sanitize_sql_array([sql, key]))
  end
  account_link_assert(label, values.all? do |row|
    row && row['value'] == 1 && row['ttl'].positive? && row['ttl'] <= 901
  end,
                      'native shared increments or expiry missing')
  5.times do |index|
    account_link_reset(user)
    before = account_link_state(user)
    client = native_client('_dawarich_session' => cookie)
    account_link_submit(client, token, 'safepassword12', 'REMOTE_ADDR' => '198.51.100.235')
    account_link_assert(label, client.response.status == (index < 4 ? 302 : 429),
                        '5/900 shared session boundary changed')
    next unless index == 4

    account_link_assert(label, account_link_state(user) == before, 'session throttle changed actor')
    account_link_assert(label, JSON.parse(client.response.body)['error'] == 'rate_limit_exceeded',
                        'session throttle body changed')
  end
  counts = owned.map do |key|
    connection.select_value(User.sanitize_sql_array(['SELECT value FROM phoenix.counters WHERE key=?', key]))
  end
  account_link_assert(label, counts == [6, 5], 'shared session short-circuit counts changed')
  ip = "rack::attack:#{fixture.fetch('at') / 900}:auth/account_link_challenge_ip:198.51.100.236"
  count = connection.select_value(User.sanitize_sql_array(['SELECT count(*) FROM phoenix.counters WHERE key=?', ip]))
  account_link_assert(label, count.zero?,
                      'IP phase owned IP key exists')
  owned << ip
  21.times do |index|
    data = fixture.dig('sessions', 'form', 'expected').deep_dup
    data['pending_oauth_link']['user_id'] = 911_457_000 + index
    key = "rack::attack:#{fixture.fetch('at') / 900}:auth/account_link_challenge_session:#{911_457_000 + index}"
    count = connection.select_value(User.sanitize_sql_array(['SELECT count(*) FROM phoenix.counters WHERE key=?', key]))
    account_link_assert(label, count.zero?,
                        'IP phase owned key exists')
    owned << key
    encoded = ActionDispatch::Request.new(Rails.application.env_config.dup).cookie_jar
    encoded.encrypted['_dawarich_session'] = { value: data }
    client = native_client('_dawarich_session' => URI.encode_www_form_component(encoded['_dawarich_session']))
    before = account_link_state(user)
    account_link_submit(client, token, 'safepassword12', 'REMOTE_ADDR' => '198.51.100.236')
    account_link_assert(label, client.response.status == (index < 20 ? 302 : 429), '20/900 IP boundary changed')
    account_link_assert(label, account_link_state(user) == before, 'IP phase changed target')
  end
  count = connection.select_value(User.sanitize_sql_array(['SELECT value FROM phoenix.counters WHERE key=?', ip]))
  account_link_assert(label, count == 21,
                      'IP count changed')
  puts "#{label}: PASS same allocated DB, native + Rails counts, expiry, 5/900, 20/900 and no effects at 429"
ensure
  Rack::Attack.enabled = previous_enabled
  Rack::Attack.cache.store = previous_store
  owned&.each { |key| ActiveRecord::Base.connection.execute(User.sanitize_sql_array(['DELETE FROM phoenix.counters WHERE key=?', key])) }
end

def consume_account_link(fixture, request)
  label = 'Rails consumes native account-link form completion and OTP no-bypass state'
  account_link_assert(label, (File.stat(ARGV.fetch(0)).mode & 0o777) == 0o600, 'private payload mode required')
  ids = [911_456_001, 911_456_002, 911_456_003]
  emails = ids.map { |id| "a11e-protocol-#{id}@example.invalid" }
  account_link_assert(label, fixture.fetch('actors').map { |actor| actor.fetch('id') } == ids &&
    fixture.fetch('actors').map { |actor| actor.fetch('email') } == emails, 'synthetic identities required')
  account_link_assert(label, !User.unscoped.where(id: ids).exists? && !User.unscoped.where(email: emails).exists?,
                      'owned actors exist')
  expected = if fixture.fetch('shared_counters')
               [
                 "rack::attack:#{fixture.fetch('at') / 900}:auth/account_link_challenge_session:#{ids.first}",
                 "rack::attack:#{fixture.fetch('at') / 900}:auth/account_link_challenge_ip:198.51.100.235"
               ]
             else
               []
             end
  account_link_assert(label, fixture.fetch('counter_keys') == expected, 'owned counter identities required')
  counter_keys = expected
  previous_csrf = ActionController::Base.allow_forgery_protection
  previous_enabled = Rack::Attack.enabled
  previous_auth = Rails.application.env_config['omniauth.auth']
  previous_mock = OmniAuth.config.mock_auth[:openid_connect]
  previous_mode = OmniAuth.config.test_mode
  created = []
  clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
  ActionController::Base.allow_forgery_protection = true
  Rack::Attack.enabled = false
  fixture.fetch('actors').each do |actor|
    user = User.create!(id: actor.fetch('id'), email: actor.fetch('email'), password: 'safepassword12',
                        settings: {}, status: :active, plan: :pro, skip_auto_trial: true, skip_family_sync: true)
    created << user
    user.update_columns(encrypted_password: actor.fetch('hash'), provider: nil, uid: nil, failed_attempts: 2,
                        sign_in_count: 0, failed_otp_attempts: 3, otp_required_for_login: user.id == ids[1],
                        active_until: 10.years.from_now)
  end
  clock.travel_to(Time.at(fixture.fetch('at')).utc) do
    fixture.fetch('sessions').each do |name, entry|
      decoded = jar(request, '_dawarich_session', entry.fetch('cookie')).encrypted['_dawarich_session']
      account_link_assert(label, decoded == entry.fetch('expected'), "#{name} decryption mismatch")
    end
    user = created.first
    cookie = fixture.dig('sessions', 'form', 'cookie')
    token = fixture.fetch('form_token')
    account_link_csrf(fixture, user, cookie, token)
    account_link_reset(user)
    client = native_client('_dawarich_session' => cookie)
    account_link_submit(client, token)
    completed = client.response.status == 302 && user.reload.sign_in_count == 1 && user.provider == 'openid_connect'
    account_link_assert(label, completed,
                        'native form completion refused')
    keys = account_link_session(client).keys & %w[pending_oauth_link pending_oauth_link_attempts]
    account_link_assert(label, keys.empty?, 'pending state retained')
    signed = native_client('_dawarich_session' => fixture.dig('sessions', 'completed', 'cookie'))
    signed.get('/stats')
    account_link_assert(label, signed.response.status == 200, 'native completed session refused')
    otp = native_client('_dawarich_session' => fixture.dig('sessions', 'otp', 'cookie'))
    otp.get('/stats')
    account_link_assert(label, otp.response.status == 302, 'OTP native link-only authenticated')
    anonymous = !account_link_session(otp).key?('warden.user.user.key') && created[1].reload.sign_in_count.zero?
    account_link_assert(label, anonymous,
                        'OTP no-bypass state changed')
    otp_confirmation = native_client('_dawarich_session' => fixture.dig('sessions', 'otp_form', 'cookie'))
    account_link_submit(otp_confirmation, fixture.fetch('foreign_token'))
    linked = otp_confirmation.response.status == 302 && created[1].reload.provider == 'openid_connect'
    anonymous = created[1].sign_in_count.zero? && !account_link_session(otp_confirmation).key?('warden.user.user.key')
    account_link_assert(label, linked && anonymous, 'OTP source form bypassed authentication')
    account_link_reset(user)
    refused = native_client('_dawarich_session' => cookie)
    1.upto(5) do |attempt|
      account_link_submit(refused, token, 'wrong')
      account_link_assert(label, refused.response.status == (attempt < 5 ? 422 : 302), 'wrong-password status changed')
      state = account_link_session(refused)
      correct_count = attempt < 5 ? state['pending_oauth_link_attempts'] == attempt : !state.key?('pending_oauth_link')
      account_link_assert(label, correct_count,
                          'wrong-password pending count changed')
    end
    email = native_client('_dawarich_session' => fixture.dig('sessions', 'email_form', 'cookie'))
    email.post('/auth/account_link/email', params: { authenticity_token: fixture.fetch('email_token') })
    account_link_assert(label, email.response.status == 302 && created[2].reload.provider.nil?,
                        'email fallback changed identity')
    account_link_reset(user)
    2.times do |index|
      replay = native_client('_dawarich_session' => cookie)
      account_link_submit(replay, token)
      account_link_assert(label, replay.response.status == 302 && user.reload.sign_in_count == index + 1,
                          'saved-cookie replay source outcome changed')
    end
    account_link_reset(user)
    account_link_overlap(user, cookie, token, label, fixture.fetch('shared_counters') ? 1 : 0)
    account_link_reset(user)
    Rails.application.routes.append do
      devise_scope :user do
        get 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
      end
    end
    Rails.application.reload_routes!
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
    OmniAuth.config.test_mode = true
    older = account_link_source_pair(user, 'a11e-protocol-old')
    newer = account_link_source_pair(user, 'a11e-protocol-new')
    [older, newer].each do |wire, form_token, state|
      replay = native_client('_dawarich_session' => wire)
      account_link_submit(replay, form_token)
      correct_identity = replay.response.status == 302 && user.reload.uid == state.dig('pending_oauth_link', 'uid')
      account_link_assert(label, correct_identity, 'superseded source outcome changed')
    end
    account_link_reset(user)
    transplanted = native_client('_dawarich_session' => older.first)
    account_link_submit(transplanted, older[1])
    account_link_assert(label, transplanted.response.status == 302 && user.reload.sign_in_count == 1,
                        'matching transplant source outcome changed')
    account_link_rates(fixture, user, cookie, token) if fixture.fetch('shared_counters')
    account_link_reset(user)
    wire, source_token, state = account_link_source_pair(user, 'a11e-source-to-native')
    fixture['rails'] = { 'cookie' => wire, 'token' => source_token, 'session' => state,
                         'hash' => user.reload.encrypted_password, 'uid' => 'a11e-source-to-native' }
    File.write(ARGV.fetch(0), JSON.generate(fixture))
  end
  puts "#{label}: PASS native form/CSRF, completed protected page, OTP no-bypass, " \
       'refusal/email and four source replay schedules'
ensure
  ActionController::Base.allow_forgery_protection = previous_csrf
  Rack::Attack.enabled = previous_enabled
  Rails.application.env_config['omniauth.auth'] = previous_auth
  OmniAuth.config.mock_auth[:openid_connect] = previous_mock
  OmniAuth.config.test_mode = previous_mode
  created&.each { |user| User.unscoped.where(id: user.id, email: user.email).delete_all }
  counter_keys&.each do |key|
    ActiveRecord::Base.connection.execute(User.sanitize_sql_array(['DELETE FROM phoenix.counters WHERE key=?', key]))
  end
end

def consume_account_update(fixture, request)
  raise 'Rails accepts native bypass: account-update mode missing' unless fixture.fetch('mode', nil) == 'account_update'

  id = fixture.fetch('user_id')
  raise 'Rails accepts native bypass: synthetic identity required' unless id == 74_003
  raise 'Rails accepts native bypass: synthetic actor already exists' if User.exists?(id:)

  user = nil
  begin
    user = User.create!(id:, email: 'a11rest-protocol@dawarich.test',
                        password: 'a11rest-protocol-old-password',
                        password_confirmation: 'a11rest-protocol-old-password',
                        settings: {}, status: :active, plan: :pro)
    user.update_columns(encrypted_password: fixture.fetch('new_hash'), locked_at: nil,
                        failed_attempts: 0, active_until: 10.years.from_now)
    raise 'Rails accepts native bcrypt: new password refused' unless user.valid_password?(fixture.fetch('new_password'))
    if user.valid_password?(fixture.fetch('old_password'))
      raise 'Rails accepts native bcrypt: old password still accepted'
    end

    fixture.fetch('sessions').each do |name, entry|
      decoded = jar(request, '_dawarich_session', entry.fetch('cookie')).encrypted['_dawarich_session']
      raise "Rails accepts native bypass: #{name} decryption failed" unless decoded == entry.fetch('expected')
    end
    updated = fixture.dig('sessions', 'updated', 'expected')
    old = fixture.dig('sessions', 'old', 'expected')
    raise 'Rails accepts native bypass: session ID changed' unless updated['session_id'] == old['session_id']
    raise 'Rails accepts native bypass: CSRF changed' unless updated['_csrf_token'] == old['_csrf_token']
    raise 'Rails accepts native bypass: return-to lost' unless updated['user_return_to'] == '/stats'
    raise 'Rails accepts native bypass: devise data retained' if updated.keys.any? { |key| key.start_with?('devise.') }

    updated_client = native_client('_dawarich_session' => fixture.dig('sessions', 'updated', 'cookie'))
    updated_client.get('/stats')
    raise 'Rails accepts native bypass: new Warden salt refused' unless updated_client.response.status == 200

    old_client = native_client('_dawarich_session' => fixture.dig('sessions', 'old', 'cookie'))
    old_client.get('/stats')
    raise 'Rails accepts native bypass: old Warden salt survived' unless old_client.response.status == 302

    puts 'Native→Rails account update: 2 sessions, bcrypt, new Warden accepted, old salt refused'
  ensure
    user&.delete
  end
end

def consume_two_factor_management(fixture, request)
  label = 'Rails consumes native OTP storage backups and management cookies'
  raise "#{label}: mode missing" unless fixture.fetch('mode', nil) == 'two_factor_management'

  id = fixture.fetch('user_id')
  email = 'a11c-protocol@dawarich.test'
  raise "#{label}: synthetic identity required" unless id == 74_603 && fixture.fetch('email') == email
  raise "#{label}: synthetic actor already exists" if User.exists?(id:) || User.exists?(email:)

  user = nil
  begin
    user = User.create!(id:, email:, password: fixture.fetch('password'), settings: {}, status: :active, plan: :pro)
    native = fixture.fetch('enabled')
    user.update_columns(encrypted_password: fixture.fetch('hash'), locked_at: nil, failed_attempts: 0,
                        otp_required_for_login: native.fetch('enabled'), otp_backup_codes: native.fetch('backups'),
                        consumed_timestep: native.fetch('consumed_timestep'), active_until: 10.years.from_now)
    User.connection.execute(User.sanitize_sql_array(['UPDATE users SET otp_secret=? WHERE id=?',
                                                     native.fetch('ciphertext'), id]))
    raise "#{label}: decryption failed" unless user.reload.otp_secret == fixture.fetch('secret')

    backup = fixture.fetch('unused_backup')
    raise "#{label}: native backup refused" unless user.invalidate_otp_backup_code!(backup)
    raise "#{label}: backup replay survived" if user.reload.invalidate_otp_backup_code!(backup)

    clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
    clock.travel_to(Time.at(fixture.fetch('at')).utc) do
      if user.validate_and_consume_otp!(fixture.fetch('current_code'))
        raise "#{label}: consumed timestep replay survived"
      end

      clock.travel_to(Time.at(fixture.fetch('at') + 30).utc)
      raise "#{label}: later timestep refused" unless user.validate_and_consume_otp!(fixture.fetch('later_code'))
      raise "#{label}: timestep not saved" unless user.reload.consumed_timestep == native.fetch('consumed_timestep') + 1

      fixture.fetch('sessions').each do |name, entry|
        decoded = jar(request, '_dawarich_session', entry.fetch('cookie')).encrypted['_dawarich_session']
        raise "#{label}: #{name} cookie mismatch" unless decoded == entry.fetch('expected')
      end
      before = fixture.dig('sessions', 'before', 'expected')
      managed = fixture.dig('sessions', 'managed', 'expected')
      raise "#{label}: Warden or session identity changed" unless before == managed

      ActionController::Base.allow_forgery_protection = true
      client = native_client('_dawarich_session' => fixture.dig('sessions', 'managed', 'cookie'))
      client.get('/settings/two_factor')
      raise "#{label}: authenticated management refused" unless client.response.status == 200

      client.post('/settings/two_factor', params: { authenticity_token: fixture.fetch('form_token') })
      raise "#{label}: setup CSRF refused" unless client.response.status == 200
      raise "#{label}: setup did not persist" unless user.reload.otp_secret != fixture.fetch('secret')

      received = client.request.cookie_jar.encrypted['_dawarich_session']
      unless received['session_id'] == before['session_id'] &&
             received['warden.user.user.key'] == before['warden.user.user.key']
        raise "#{label}: management lost Warden identity"
      end

      disabled = fixture.fetch('disabled')
      raise "#{label}: native disable projection wrong" unless disabled == {
        'enabled' => false, 'ciphertext' => nil, 'backups' => nil,
        'consumed_timestep' => native.fetch('consumed_timestep')
      }

      user.update_columns(otp_required_for_login: false, otp_secret: nil, otp_backup_codes: nil,
                          consumed_timestep: disabled.fetch('consumed_timestep'))
      login = native_client({})
      login.get('/users/sign_in')
      token = Nokogiri::HTML5(login.response.body).at_css('meta[name="csrf-token"]')['content']
      login.post('/users/sign_in', params: { authenticity_token: token,
                                           user: { email:, password: fixture.fetch('password') } })
      raise "#{label}: ordinary login refused after disable" unless login.response.status == 303

      login.get('/stats')
      raise "#{label}: ordinary session refused" unless login.response.status == 200
    end
    puts "#{label}: PASS decryption, backup once/replay, timestep once/later, " \
         'setup CSRF, retained Warden, disabled login'
  ensure
    user&.delete
  end
end

def api_protocol_assert(condition, detail)
  raise "Rails accepts native API secret and backup once: #{detail}" unless condition
end

def install_api_projection(user, native, hash)
  user.update_columns(encrypted_password: hash, otp_required_for_login: native.fetch('enabled'),
                      otp_backup_codes: native.fetch('backups'), consumed_timestep: native.fetch('consumed_timestep'))
  User.connection.execute(User.sanitize_sql_array(['UPDATE users SET otp_secret=? WHERE id=?',
                                                   native.fetch('ciphertext'), user.id]))
  user.reload
end

def consume_api_password_work(fixture)
  label = 'API password native preflight doubles actual Rails work for the same actor or miss'
  id = 911_510_010
  email = 'a11f-password-work@example.invalid'
  rows = fixture.fetch('rows')
  names = %w[known-wrong known-wrong-low-cost known-wrong-2a-low-cost rejected-2a-low-cost
             rejected-2y-low-cost rejected-2x-low-cost wrong-nul-known wrong-nul-unknown wrong-nul-deleted
             correct-nul correct-nul-otp wrong-nul-form correct-nul-form unicode-known unicode-unknown unicode-deleted
             unknown deleted blank-hash
             provider provider-low-cost
             settings settings-low-cost metadata metadata-low-cost validation validation-low-cost]
  names += %w[2a 2b 2x 2y].product(%w[00 01 02 03 32 99]).map { |minor, rounds| "uncomputable-#{minor}-#{rounds}" }
  names += %w[uncomputable-2z uncomputable-1a invalid-hash]
  unless fixture['id'] == id && fixture['email'] == email &&
         rows.map { |row| row['name'] } == names &&
         File.stat(ARGV.fetch(0)).mode & 0o777 == 0o600
    raise "#{label}: owned payload required"
  end
  raise "#{label}: actor collision" if User.unscoped.where(id: id).exists? || User.unscoped.where(email: email).exists?

  dummy_hash = Api::V1::Auth::SessionsController::DUMMY_PASSWORD_HASH
  cost = BCrypt::Password.new(dummy_hash).cost
  raise "#{label}: source dummy cost mismatch" unless fixture.fetch('dummy_cost') == cost

  BCrypt::Engine.singleton_class.prepend(Module.new do
    define_method(:hash_secret) do |*args|
      result = super(*args)
      Thread.current[:a11f_password_work]&.push(args[1].split('$')[2].to_i) if result
      result
    end
  end)
  previous_attack = Rack::Attack.enabled
  previous_work = Thread.current[:a11f_password_work]
  baseline = nil
  begin
    Rack::Attack.enabled = false
    rows.each do |row|
      state = row.fetch('state')
      raise "#{label}: actor id mismatch" unless state['id'] == id

      columns = state.keys.join(',')
      values = state.keys.map { |field| "r.#{field}" }.join(',')
      sql = "INSERT INTO users (#{columns},created_at,updated_at) " \
            "SELECT #{values},now(),now() FROM jsonb_populate_record(NULL::users,?::jsonb) r"
      User.connection.execute(User.sanitize_sql_array([sql, JSON.generate(state)]))
      before = User.unscoped.find(id).attributes
      Thread.current[:a11f_password_work] = []
      client = native_client({})
      failure = nil
      begin
        client.post('/api/v1/auth/login', params: row.fetch('raw'), headers: { 'CONTENT_TYPE' => row.fetch('type') })
      rescue BCrypt::Errors::InvalidHash, ArgumentError => e
        failure = e
      end
      source_work = Thread.current[:a11f_password_work]
      if row['name'].include?('nul')
        unless row.fetch('native_work').empty? && row.fetch('native_lookups').zero? && source_work.empty? &&
               failure.is_a?(ArgumentError) && failure.message == 'string contains null byte' &&
               User.unscoped.find(id).attributes == before
          raise "#{label}: #{row['name']} NUL admission or source outcome changed"
        end

        User.unscoped.find(id).delete
        next
      end
      if row['name'] == 'invalid-hash'
        unless row.fetch('native_work').empty? && row.fetch('native_lookups') == 1 && source_work.empty? &&
               failure.is_a?(BCrypt::Errors::InvalidHash) && User.unscoped.find(id).attributes == before
          raise "#{label}: invalid hash exception ownership changed"
        end

        User.unscoped.find(id).delete
        next
      end
      raise "#{label}: unexpected source exception" if failure

      if row['name'].start_with?('unicode')
        expected_cost = row['name'] == 'unicode-known' ? BCrypt::Password.new(state['encrypted_password']).cost : cost
        unless row.fetch('native_work').empty? && row.fetch('native_lookups').zero? &&
               source_work == [expected_cost]
          raise "#{label}: Unicode replay work mismatch"
        end
      else
        raise "#{label}: lookup trace mismatch" unless row.fetch('native_lookups') == 1
      end

      combined = row.fetch('native_work') + source_work
      source_expected =
        case row['name']
        when 'blank-hash', /\Auncomputable-/ then []
        when 'unknown', 'deleted', 'unicode-unknown', 'unicode-deleted' then [cost]
        else [BCrypt::Password.new(state.fetch('encrypted_password')).cost]
        end
      native_expected = if row['name'].start_with?('unicode')
                          []
                        else
                          source_expected.empty? ? [cost, cost] : source_expected
                        end
      rails_baseline = source_work.empty? ? [cost] : source_work
      combined_expected = row['name'].start_with?('unicode') ? source_work : rails_baseline * 2
      raise "#{label}: #{row['name']} native work mismatch" unless row['native_work'] == native_expected
      raise "#{label}: #{row['name']} source work mismatch" unless source_work == source_expected
      raise "#{label}: #{row['name']} combined work mismatch" unless combined == combined_expected

      body = JSON.parse(client.response.body)
      baseline ||= body
      unless client.response.status == 401 && body == baseline && !client.response.headers['Set-Cookie'] &&
             User.unscoped.find(id).attributes == before
        raise "#{label}: #{row['name']} refusal contract or state changed"
      end

      User.unscoped.find(id).delete
    end
    puts "#{label}: PASS combined work doubles each Rails-only pattern; blank hash compensated; " \
         "NUL replay has no native lookup/work; dummy cost #{cost}"
  ensure
    Thread.current[:a11f_password_work] = previous_work
    Rack::Attack.enabled = previous_attack
    User.unscoped.where(id: id).delete_all
  end
end

def consume_api_otp_work(fixture)
  label = 'API OTP preflight mirrors actual Rails read-only verification work'
  id = 911_510_011
  email = 'a11f-otp-work@example.invalid'
  unless fixture['id'] == id && fixture['email'] == email && File.stat(ARGV.fetch(0)).mode & 0o777 == 0o600
    raise "#{label}: owned payload required"
  end
  raise "#{label}: actor collision" if User.unscoped.where(id: id).exists? || User.unscoped.where(email: email).exists?

  previous_env = fixture.fetch('env').keys.index_with { |key| ENV[key] }
  encryption = ActiveRecord::Encryption.config
  previous_encryption = %i[primary_key deterministic_key key_derivation_salt].index_with do |key|
    encryption.public_send(key)
  end
  previous_cache = Rails.cache
  previous_attack = Rack::Attack.enabled
  previous_work = Thread.current[:a11f_otp_work]
  clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
  BCrypt::Engine.singleton_class.prepend(Module.new do
    define_method(:hash_secret) do |*args|
      result = super(*args)
      Thread.current[:a11f_otp_work]&.push(args[1].split('$')[2].to_i) if result
      result
    end
  end)
  ROTP::OTP.prepend(Module.new do
    define_method(:generate_otp) do |*args|
      result = super(*args)
      Thread.current[:a11f_otp_work]&.push('totp')
      result
    end
  end)
  begin
    Rack::Attack.enabled = false
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    previous_env.each_key { |key| fixture['env'][key].nil? ? ENV.delete(key) : ENV[key] = fixture['env'][key] }
    ActiveRecord::Encryption.configure(primary_key: fixture['env']['OTP_ENCRYPTION_PRIMARY_KEY'],
                                       deterministic_key: fixture['env']['OTP_ENCRYPTION_DETERMINISTIC_KEY'],
                                       key_derivation_salt: fixture['env']['OTP_ENCRYPTION_KEY_DERIVATION_SALT'])
    clock.travel_to(Time.at(fixture.fetch('at')).utc) do
      fixture.fetch('rows').each do |row|
        row_env = row.fetch('env')
        previous_env.each_key { |key| row_env[key].nil? ? ENV.delete(key) : ENV[key] = row_env[key] }
        ActiveRecord::Encryption.configure(primary_key: row_env['OTP_ENCRYPTION_PRIMARY_KEY'],
                                           deterministic_key: row_env['OTP_ENCRYPTION_DETERMINISTIC_KEY'],
                                           key_derivation_salt: row_env['OTP_ENCRYPTION_KEY_DERIVATION_SALT'])
        state = row.fetch('state')
        raise "#{label}: actor id mismatch" unless state['id'] == id && state['email'] == email

        columns = state.keys.join(',')
        values = state.keys.map { |field| "r.#{field}" }.join(',')
        sql = "INSERT INTO users (#{columns},status,plan,subscription_source,created_at,updated_at) " \
              "SELECT #{values},1,1,0,now(),now() FROM jsonb_populate_record(NULL::users,?::jsonb) r"
        User.connection.execute(User.sanitize_sql_array([sql, JSON.generate(state)]))
        Thread.current[:a11f_otp_work] = []
        client = native_client({})
        failure = nil
        begin
          client.post('/api/v1/auth/otp_challenge',
                      params: { challenge_token: fixture.fetch('token'), otp_code: row.fetch('code') }, as: :json)
        rescue ActiveRecord::Encryption::Errors::Decryption, ROTP::Base32::Base32Error,
               BCrypt::Errors::InvalidHash, ArgumentError => e
          failure = e
        end
        source_work = Thread.current[:a11f_otp_work]
        expected = row.fetch('expected_work')
        unless source_work == expected && row.fetch('native_work') == source_work
          raise "#{label}: #{row['name']} work mismatch: " \
                "source=#{source_work.inspect}, native=#{row['native_work'].inspect}"
        end

        if %w[unreadable-secret invalid-secret invalid-backup].include?(row['name'])
          raise "#{label}: #{row['name']} exception changed" unless failure
        else
          raise "#{label}: #{row['name']} unexpected exception" if failure

          expected_status = if %w[provider-totp provider-backup legacy-backup nil-secret-backup].include?(row['name'])
                              200
                            elsif row['name'].start_with?('locked')
                              423
                            else
                              401
                            end
          unless client.response.status == expected_status && !client.response.headers['Set-Cookie']
            raise "#{label}: #{row['name']} source response changed"
          end
        end
        User.unscoped.find(id).delete
        Rails.cache.clear
      end
      fixture.fetch('out_of_range_tokens').each do |token|
        Thread.current[:a11f_otp_work] = []
        client = native_client({})
        client.post('/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: 'wrong' }, as: :json)
        unless client.response.status == 401 && JSON.parse(client.response.body)['error'] == 'auth_failed' &&
               !client.response.headers['Set-Cookie'] && Thread.current[:a11f_otp_work].empty?
          raise "#{label}: out-of-range JWT source refusal changed"
        end
      end
    end
    puts "#{label}: PASS supported/provider/legacy/secret-state/locked/success controls; replay before native writes"
  ensure
    Thread.current[:a11f_otp_work] = previous_work
    previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    ActiveRecord::Encryption.configure(**previous_encryption)
    Rails.cache = previous_cache
    Rack::Attack.enabled = previous_attack
    User.unscoped.where(id: id).delete_all
  end
end

def consume_api_auth(fixture)
  label = 'Rails accepts native API challenges and rejects native consumed JTIs'
  continuity = 'API auth shared RDB retains the same live actors and markers across runtimes'
  ids = [911_510_001, 911_510_002, 911_510_003, 911_510_004]
  emails = ids.map { |id| "a11f-protocol-#{id}@example.invalid" }
  actors = fixture.fetch('actors')
  shared = fixture.fetch('lifecycle') == 'shared_rdb'
  raise "#{label}: lifecycle refused" unless %w[projection shared_rdb].include?(fixture['lifecycle'])
  raise "#{label}: owned payload required" unless actors.map { |actor| actor['id'] } == ids &&
                                                  actors.map { |actor| actor['email'] } == emails &&
                                                  File.stat(ARGV.fetch(0)).mode & 0o777 == 0o600

  previous_cache = Rails.cache
  previous_attack = Rack::Attack.enabled
  previous_env = fixture.fetch('env').keys.grep(/\AOTP_ENCRYPTION_|\AJWT_SECRET_KEY\z/).index_with { |key| ENV[key] }
  encryption = ActiveRecord::Encryption.config
  previous_encryption = %i[primary_key deterministic_key key_derivation_salt].index_with do |key|
    encryption.public_send(key)
  end
  redis = Redis.new(url: "#{ENV.fetch('REDIS_URL')}/0", driver: :ruby)
  keys = fixture.fetch('marker_keys').dup
  keys << "otp_lockout_email_throttle/user/#{ids.last}"
  success = false
  clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
  state = lambda do |id|
    query = ['SELECT to_jsonb(users) FROM users WHERE id=? AND email=?',
             id, "a11f-protocol-#{id}@example.invalid"]
    row = User.connection.select_value(User.sanitize_sql_array(query))
    row = JSON.parse(row) if row.is_a?(String)
    row&.slice(*actors.first.fetch('state').keys)
  end
  submit = lambda do |token, code|
    client = native_client({})
    client.post('/api/v1/auth/otp_challenge', params: { challenge_token: token, otp_code: code }, as: :json)
    client
  end
  begin
    unless redis.connection[:db].zero? && redis._client.options[:driver] == Redis::Connection::Ruby
      raise "#{label}: real Ruby cache driver DB zero required"
    end

    Rails.cache = ActiveSupport::Cache::RedisCacheStore.new(redis: redis, error_handler: ->(**_failure) {})
    Rack::Attack.enabled = false
    previous_env.each_key { |key| fixture['env'][key].nil? ? ENV.delete(key) : ENV[key] = fixture['env'][key] }
    ActiveRecord::Encryption.configure(primary_key: fixture['env']['OTP_ENCRYPTION_PRIMARY_KEY'],
                                       deterministic_key: fixture['env']['OTP_ENCRYPTION_DETERMINISTIC_KEY'],
                                       key_derivation_salt: fixture['env']['OTP_ENCRYPTION_KEY_DERIVATION_SALT'])
    unless Auth::InternalTokenSecret.call == 'phoenix-a2-cookie-fixture-secret-not-for-production'
      raise "#{label}: source secret mismatch"
    end

    if shared
      actors.each { |actor| raise "#{continuity}: row mismatch" unless state.call(actor['id']) == actor['state'] }
      puts "#{continuity}: PASS source observes native persisted rows"
    else
      if User.unscoped.where(id: ids).exists? || User.unscoped.where(email: emails).exists?
        raise "#{label}: owned row collision"
      end

      actors.each do |actor|
        fields = actor.fetch('state').keys
        columns = fields.join(',')
        values = fields.map { |field| "r.#{field}" }.join(',')
        sql = "INSERT INTO users (#{columns},status,plan,subscription_source,created_at,updated_at) " \
              "SELECT #{values},1,1,0,now(),now() FROM jsonb_populate_record(NULL::users,?::jsonb) r"
        User.connection.execute(User.sanitize_sql_array([sql, JSON.generate(actor['state'])]))
      end
    end
    clock.travel_to(Time.at(fixture.fetch('at')).utc) do
      Time.use_zone('UTC') do
        clock.travel_to(Time.at(fixture.fetch('at') + 30).utc)
        replay = submit.call(actors.first.fetch('token'), ROTP::TOTP.new(fixture.fetch('secret')).at(Time.current))
        raise "#{label}: native consumed JTI accepted" unless replay.response.status == 401

        marker = fixture['marker_keys'].first
        unless Rails.cache.read(marker) == true && redis.pttl(marker).between?(1, 300_000)
          raise "#{label}: native cache marker TTL mismatch"
        end

        clock.travel_to(Time.at(fixture.fetch('at')).utc)
        [actors[1], actors[2]].each_with_index do |actor, index|
          code = index.zero? ? ROTP::TOTP.new(fixture.fetch('secret')).at(Time.current) : 'a11f backup one'
          client = submit.call(actor.fetch('token'), code)
          raise "#{label}: native challenge refused" unless client.response.status == 200
          raise "#{label}: web cookie issued" if client.response.headers['Set-Cookie']

          result = JSON.parse(client.response.body)
          raise "#{label}: subject key changed" unless result['api_key'] == actor['state']['api_key']

          reader = native_client({})
          reader.get('/api/v1/users/me', headers: { 'Authorization' => "Bearer #{result['api_key']}" })
          raise "#{label}: source API reader refused" unless reader.response.status == 200

          user = User.find(actor['id'])
          raise "#{label}: reset mismatch" unless user.failed_otp_attempts.zero? && user.otp_locked_at.nil?
          raise "#{label}: timestep mismatch" if index.zero? && user.consumed_timestep != fixture['at'] / 30
          raise "#{label}: backup not removed" if index == 1 && user.otp_backup_codes.size != 1

          marker = "otp_challenge:consumed:#{actor['jti']}"
          unless Rails.cache.read(marker) == true && redis.pttl(marker).between?(1, 300_000)
            raise "#{label}: source cache marker TTL mismatch"
          end
        end
        before_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size
        refusal = submit.call(actors.last.fetch('token'), 'invalid otp')
        user = User.find(ids.last)
        unless refusal.response.status == 401 && user.failed_otp_attempts == 10 && user.otp_locked?
          raise "#{label}: invalid code effects mismatch"
        end

        locked = submit.call(actors.last.fetch('token'), ROTP::TOTP.new(fixture.fetch('secret')).at(Time.current))
        unless locked.response.status == 423 && user.reload.failed_otp_attempts == 10 &&
               ActiveJob::Base.queue_adapter.enqueued_jobs.size == before_jobs + 1
          raise "#{label}: lockout effects duplicated"
        end

        source_actors = actors.map do |actor|
          token = Auth::IssueOtpChallengeToken.new(User.find(actor['id'])).call
          claims, = JWT.decode(token, Auth::InternalTokenSecret.call, true, algorithm: 'HS256')
          key = "otp_challenge:consumed:#{claims['jti']}"
          keys << key
          { 'id' => actor['id'], 'email' => actor['email'], 'token' => token, 'jti' => claims['jti'],
            'state' => state.call(actor['id']) }
        end
        races = JSON.parse(File.read(Rails.root.join('app-phoenix/test/fixtures/auth/api_auth/races.json')))
        fixture['rails'] = { 'actors' => source_actors, 'marker_keys' => keys - fixture['marker_keys'],
                             'source_races' => races }
        if fixture['mobile']
          mobile = fixture.fetch('mobile')
          decoded, = JWT.decode(mobile.fetch('token'), mobile.fetch('secret'), true, algorithm: 'HS256')
          unless decoded == { 'api_key' => 'synthetic-mobile-key', 'exp' => fixture.fetch('at') + 300 }
            raise 'Native mobile token refused by Rails'
          end

          bytes = Base64.strict_decode64(mobile.fetch('watermark'))
          coder = Rails.cache.instance_variable_get(:@coder)
          raise 'Native callback watermark refused by Rails' unless coder.load(bytes).value == 1_790_000_000_000

          fixture['rails']['mobile'] = Subscription::EncodeJwtToken.new(
            { api_key: 'synthetic-mobile-key', exp: fixture.fetch('at') + 300 }, mobile.fetch('secret')
          ).call
        end
        File.write(ARGV.fetch(0), JSON.generate(fixture))
      end
    end
    puts "#{label}: PASS source JWT, controller, cache, key reader and lockout"
    success = true
  ensure
    clock.travel_back
    User.unscoped.where(id: ids, email: emails).delete_all unless success && shared
    keys.each { |key| redis.del(key) } unless success
    redis.close
    Rails.cache = previous_cache
    Rack::Attack.enabled = previous_attack
    previous_env.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    ActiveRecord::Encryption.configure(**previous_encryption)
  end
end

def consume_api_two_factor_management(fixture)
  ids = [954_801, 954_802, 954_803]
  emails = ids.map { |id| "a4otp-protocol-#{id}@example.invalid" }
  actors = fixture.fetch('actors')
  api_protocol_assert(fixture.fetch('schema') == 1, 'schema mismatch')
  api_protocol_assert(actors.map { |actor| actor.fetch('id') } == ids, 'identity mismatch')
  api_protocol_assert(actors.map { |actor| actor.fetch('email') } == emails, 'email mismatch')
  api_protocol_assert(!User.where(id: ids).exists? && !User.where(email: emails).exists?, 'synthetic actor exists')
  api_protocol_assert((fixture.keys & %w[sessions cookie token remember form_token]).empty?, 'session issued')
  created = []
  clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)

  begin
    actors.each do |actor|
      user = User.create!(id: actor.fetch('id'), email: actor.fetch('email'),
                          password: fixture.fetch('password'), settings: {}, status: :active, plan: :pro)
      created << user
      confirmed = actor.fetch('confirmed')
      api_protocol_assert(confirmed.fetch('consumed_timestep').nil?, 'API confirm consumed timestep')
      api_protocol_assert(confirmed.fetch('enabled') == (user.id != 954_803), 'enabled flag changed')

      [confirmed, actor['consumed']].compact.each do |native|
        install_api_projection(user, native, actor.fetch('hash'))
        api_protocol_assert(user.otp_secret == actor.fetch('secret'), 'decryption failed')
        backup = actor.fetch('unused_backup')
        api_protocol_assert(user.invalidate_otp_backup_code!(backup), 'native backup refused')
        api_protocol_assert(!user.reload.invalidate_otp_backup_code!(backup), 'backup replay survived')
        next unless actor.fetch('secret')

        clock.travel_to(Time.at(fixture.fetch('at')).utc) do
          accepted = user.validate_and_consume_otp!(actor.fetch('current_code'))
          api_protocol_assert(accepted == native.fetch('consumed_timestep').nil?, 'current timestep mismatch')
          replay_rejected = !user.reload.validate_and_consume_otp!(actor.fetch('current_code'))
          api_protocol_assert(replay_rejected, 'TOTP replay survived')
          clock.travel_to(Time.at(fixture.fetch('at') + 30).utc)
          api_protocol_assert(user.validate_and_consume_otp!(actor.fetch('later_code')), 'later timestep refused')
          api_protocol_assert(user.reload.consumed_timestep == fixture.fetch('at') / 30 + 1, 'later save mismatch')
        end
      end

      install_api_projection(user, confirmed, actor.fetch('hash'))
      client = native_client({})
      clock.travel_to(Time.at(fixture.fetch('at')).utc) do
        client.delete('/api/v1/users/me/two_factor',
                      params: { password: fixture.fetch('password'), otp_code: actor.fetch('unused_backup') },
                      headers: { 'Authorization' => "Bearer #{user.api_key}", 'Accept' => 'application/json' })
      end
      api_protocol_assert(client.response.status == 200, 'API controller disable refused')
      api_protocol_assert(user.reload.otp_backup_codes == [] && user.otp_secret.nil? &&
                          !user.otp_required_for_login?, 'Rails disable projection mismatch')
      disabled = actor.fetch('disabled')
      api_protocol_assert(disabled.fetch('backups') == [] && disabled.fetch('ciphertext').nil? &&
                          disabled.fetch('enabled') == false, 'native disable projection mismatch')
      expected_step = actor['consumed']&.fetch('consumed_timestep')
      api_protocol_assert(disabled.fetch('consumed_timestep') == expected_step, 'native disable lost consumption')
      install_api_projection(user, disabled, actor.fetch('hash'))
      api_protocol_assert(user.otp_backup_codes == [] && user.otp_secret.nil?, 'native empty array not preserved')
    end
    puts 'Rails accepts native API secret and backup once: PASS all API storage checks'
  ensure
    created.each(&:delete)
  end
end

def web_otp_session(client)
  request = ActionDispatch::Request.new(Rails.application.env_config.dup)
  ActionDispatch::Cookies::CookieJar.build(request,
                                           '_dawarich_session' => client.cookies['_dawarich_session'])
                                    .encrypted['_dawarich_session']
end

def web_otp_submit(client, code, token)
  client.post('/users/otp_challenge', params: { authenticity_token: token, otp_attempt: code })
end

def web_otp_clear!(data, label)
  keys = %w[otp_user_id otp_challenge_at otp_failed_attempts otp_remember_me]
  raise "#{label}: completed challenge keys retained" if keys.any? { |key| data.key?(key) }
end

def consume_web_otp(fixture, request)
  label = 'Rails consumes native pending success and refusal state without duplicate OTP effects'
  raise "#{label}: mode missing" unless fixture.fetch('mode', nil) == 'web_otp'
  raise "#{label}: own DB required" unless ENV.fetch('DATABASE_NAME').start_with?('dawarich_test')
  raise "#{label}: private payload required" unless File.stat(ARGV.fetch(0)).mode & 0o777 == 0o600

  id = fixture.fetch('user_id')
  email = 'a11d-protocol@dawarich.test'
  raise "#{label}: synthetic identity required" unless id == 75_603 && fixture.fetch('email') == email
  raise "#{label}: synthetic actor already exists" if User.exists?(id:) || User.exists?(email:)

  env = fixture.fetch('env')
  ActiveRecord::Encryption.configure(primary_key: env.fetch('OTP_ENCRYPTION_PRIMARY_KEY'),
                                     deterministic_key: env.fetch('OTP_ENCRYPTION_DETERMINISTIC_KEY'),
                                     key_derivation_salt: env.fetch('OTP_ENCRYPTION_KEY_DERIVATION_SALT'))
  ActionController::Base.allow_forgery_protection = true
  UsersMailer.default from: 'a11d-synthetic@dawarich.test'
  key = "otp_lockout_email_throttle/user/#{id}"
  raise "#{label}: synthetic throttle already exists" if Rails.cache.exist?(key)

  user = nil
  clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
  begin
    user = User.create!(id:, email:, password: 'safepassword12', settings: {}, status: :active, plan: :pro)
    user.update_columns(encrypted_password: fixture.fetch('hash'), otp_required_for_login: true,
                        otp_backup_codes: [fixture.fetch('hash')], failed_attempts: 0,
                        active_until: 10.years.from_now)
    User.connection.execute(User.sanitize_sql_array(['UPDATE users SET otp_secret=? WHERE id=?',
                                                     fixture.fetch('ciphertext'), id]))
    raise "#{label}: ciphertext refused" unless user.reload.otp_secret == fixture.fetch('secret')

    clock.travel_to(Time.at(fixture.fetch('at')).utc) do
      fixture.fetch('sessions').each do |name, entry|
        decoded = jar(request, '_dawarich_session', entry.fetch('cookie')).encrypted['_dawarich_session']
        raise "#{label}: #{name} decryption failed" unless decoded == entry.fetch('expected')
      end
      pending = fixture.dig('sessions', 'pending', 'cookie')
      token = fixture.fetch('form_token')
      client = native_client('_dawarich_session' => pending)
      web_otp_submit(client, fixture.fetch('code'), token)
      raise "#{label}: valid source completion refused" unless client.response.status == 302
      raise "#{label}: remember carry-through lost" if client.cookies['remember_user_token'].blank?

      web_otp_clear!(web_otp_session(client), label)
      unless user.reload.consumed_timestep == fixture.fetch('at') / 30 && user.failed_otp_attempts.zero? &&
             user.sign_in_count == 1
        raise "#{label}: source completion deltas wrong"
      end

      user.update_columns(consumed_timestep: nil, failed_otp_attempts: 0, sign_in_count: 0,
                          remember_created_at: nil, otp_locked_at: nil)
      client = native_client('_dawarich_session' => pending)
      1.upto(5) do |attempt|
        web_otp_submit(client, 'not-a-code', token)
        raise "#{label}: refusal accounting wrong" unless user.reload.failed_otp_attempts == attempt

        if attempt < 5
          doc = Nokogiri::HTML5(client.response.body)
          field = doc.at_css('input[name="otp_attempt"]')
          unless client.response.status == 422 && field && field['value'].to_s.empty?
            raise "#{label}: refusal markup wrong"
          end

          token = doc.at_css('meta[name="csrf-token"]')['content']
        else
          raise "#{label}: fifth refusal status wrong" unless client.response.status == 302

          web_otp_clear!(web_otp_session(client), label)
        end
      end

      user.update_columns(failed_otp_attempts: 9)
      client = native_client('_dawarich_session' => pending)
      before = ActiveJob::Base.queue_adapter.enqueued_jobs.size
      web_otp_submit(client, 'not-a-code', fixture.fetch('form_token'))
      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.drop(before)
      unless user.reload.failed_otp_attempts == 10 && user.otp_locked? &&
             jobs.count { |job| job[:job] == ActionMailer::MailDeliveryJob } == 1
        raise "#{label}: tenth refusal lock mail wrong"
      end

      web_otp_submit(client, 'not-a-code', fixture.fetch('form_token'))
      raise "#{label}: lock mail duplicated" unless ActiveJob::Base.queue_adapter.enqueued_jobs.size == before + 1

      client = native_client('_dawarich_session' => pending)
      web_otp_submit(client, 'safepassword12', fixture.fetch('form_token'))
      unless client.response.status == 302 && user.reload.failed_otp_attempts.zero? &&
             user.otp_locked_at.nil? && user.otp_backup_codes.empty?
        raise "#{label}: locked backup recovery refused"
      end

      user.update_columns(consumed_timestep: fixture.fetch('consumed_timestep'),
                          otp_backup_codes: fixture.fetch('backups'),
                          remember_created_at: Time.iso8601(fixture.fetch('remember_created_at')))
      web_otp_clear!(fixture.dig('sessions', 'completed', 'expected'), label)
      client = native_client('_dawarich_session' => fixture.dig('sessions', 'completed', 'cookie'))
      client.get('/stats')
      raise "#{label}: native Warden refused" unless client.response.status == 200

      web_otp_clear!(web_otp_session(client), label)
      raise "#{label}: native timestep replay survived" if user.reload.validate_and_consume_otp!(fixture.fetch('code'))
      raise "#{label}: native backup replay survived" if user.reload.invalidate_otp_backup_code!('safepassword12')

      remember = fixture.fetch('remember_cookie')
      remembered = native_client('remember_user_token' => remember)
      remembered.get('/stats')
      raise "#{label}: native remember refused" unless remembered.response.status == 200

      csrf = Nokogiri::HTML5(remembered.response.body).at_css('meta[name="csrf-token"]')['content']
      clock.travel_to(Time.at(fixture.fetch('at') + 1).utc)
      remembered.delete('/users/sign_out', params: { authenticity_token: csrf })
      raise "#{label}: logout refused" unless remembered.response.status == 303

      replay = native_client('remember_user_token' => remember)
      replay.get('/stats')
      raise "#{label}: remember replay survived logout" unless replay.response.status == 302

      user.update_columns(consumed_timestep: nil, otp_backup_codes: [fixture.fetch('hash')])
      first = User.find(id)
      second = User.find(id)
      unless first.validate_and_consume_otp!(fixture.fetch('code')) &&
             second.validate_and_consume_otp!(fixture.fetch('code'))
        raise "#{label}: source stale TOTP schedule changed"
      end
      if user.reload.validate_and_consume_otp!(fixture.fetch('code'))
        raise "#{label}: source sequential TOTP replay survived"
      end

      first = User.find(id)
      second = User.find(id)
      unless first.invalidate_otp_backup_code!('safepassword12') && second.invalidate_otp_backup_code!('safepassword12')
        raise "#{label}: source stale backup schedule changed"
      end
      if user.reload.invalidate_otp_backup_code!('safepassword12')
        raise "#{label}: source sequential backup replay survived"
      end

      user.update!(otp_secret: fixture.fetch('secret'),
                   encrypted_password: Devise::Encryptor.digest(User, 'safepassword12'),
                   otp_backup_codes: [Devise::Encryptor.digest(User, 'a11d-source-backup')])
      user.update_columns(consumed_timestep: nil, failed_otp_attempts: 0, otp_locked_at: nil,
                          remember_created_at: nil)
      source_client = native_client({})
      clock.travel_to(Time.at(fixture.fetch('at')).utc)
      source_client.get('/users/sign_in')
      csrf = Nokogiri::HTML5(source_client.response.body).at_css('meta[name="csrf-token"]')['content']
      source_client.post('/users/sign_in', params: { authenticity_token: csrf,
                                                   user: { email:, password: 'safepassword12', remember_me: '1' } })
      raise "#{label}: source pending initiation refused" unless source_client.response.status == 422

      source_label = 'Rails source pending challenge uses fixture time for reverse proof'
      unless web_otp_session(source_client).fetch('otp_challenge_at') == fixture.fetch('at')
        raise "#{source_label}: source challenge timestamp differs from fixture time"
      end

      user.reload
      ciphertext = User.connection.select_value(
        User.sanitize_sql_array(['SELECT otp_secret FROM users WHERE id=?', id])
      )
      fixture['rails'] = {
        'ciphertext' => ciphertext,
        'hash' => user.encrypted_password, 'backups' => user.otp_backup_codes,
        'cookie' => URI.encode_www_form_component(source_client.cookies['_dawarich_session']),
        'session' => web_otp_session(source_client),
        'form_token' => Nokogiri::HTML5(source_client.response.body).at_css('meta[name="csrf-token"]')['content']
      }
      File.write(ARGV.fetch(0), JSON.generate(fixture))
      puts "#{source_label}: PASS"
    end
    puts "#{label}: PASS CSRF, success, five refusals, tenth lock mail once, locked backup, cleared keys, " \
         'Warden, remember/logout, sequential replay and source stale-read limits'
  ensure
    Rails.cache.delete(key) if user
    user&.delete
  end
end

case ARGV[1]
when 'account_link_stand', 'account_link_stand_cleanup', 'account_link_stand_verify'
  raise 'Allocated stand database required' unless ENV.fetch('DATABASE_NAME') == 'dawarich_test_rel2b1'
  raise 'Private stand payload required' unless (File.stat(ARGV.fetch(0)).mode & 0o777) == 0o600

  ids = [911_456_101, 911_456_102, 911_456_103]
  emails = ids.map { |id| "a11e-stand-#{id}@example.invalid" }
  if mode == 'account_link_stand_verify'
    actors = ids.zip(emails).map { |id, email| User.unscoped.find_by!(id:, email:) }
    raise 'Correct confirmation did not link and authenticate' unless actors[0].provider == 'openid_connect' &&
                                                                      actors[0].uid == "a11e-stand-#{ids[0]}" &&
                                                                      actors[0].sign_in_count.positive?
    raise 'Refusal or email changed identity' unless actors[1].provider.nil? && actors[1].uid.nil? &&
                                                     actors[1].sign_in_count.zero?
    raise 'OTP link authenticated' unless actors[2].provider == 'openid_connect' &&
                                          actors[2].uid == "a11e-stand-#{ids[2]}" && actors[2].sign_in_count.zero?

    puts 'Rails account-link stand state: PASS linked sign-in, unchanged refusal, OTP link without authentication'
  elsif mode == 'account_link_stand_cleanup'
    ids.zip(emails).each do |id, email|
      User.unscoped.where(id:, email:).delete_all
      Rails.cache.delete("oauth_account_link:rate_limit:#{id}")
    end
    puts 'Rails account-link stand actors: CLEANED'
  else
    existing = User.unscoped.where(id: ids).exists? || User.unscoped.where(email: emails).exists?
    raise 'Stand actors already exist' if existing

    Rails.application.routes.append do
      devise_scope :user do
        get 'users/auth/openid_connect/callback', to: 'users/omniauth_callbacks#openid_connect'
      end
    end
    Rails.application.reload_routes!
    Rails.application.env_config['devise.mapping'] = Devise.mappings[:user]
    OmniAuth.config.test_mode = true
    ActionController::Base.allow_forgery_protection = true
    fixture['actors'] = ids.zip(emails).map do |id, email|
      user = User.create!(id:, email:, password: 'safepassword12', settings: {}, status: :active,
                          plan: :pro, skip_auto_trial: true, skip_family_sync: true)
      user.update_columns(otp_required_for_login: id == ids.last, active_until: 10.years.from_now)
      wire, _token, state = account_link_source_pair(user, "a11e-stand-#{id}")
      raise 'Source pending identity missing' unless state.dig('pending_oauth_link', 'user_id') == id
      raise 'Source pending identity authenticated' if state.key?('warden.user.user.key')

      { 'id' => id, 'email' => email, 'cookie' => wire }
    end
    clock = Object.new.extend(ActiveSupport::Testing::TimeHelpers)
    clock.travel_to(20.minutes.ago) do
      user = User.unscoped.find_by!(id: ids[1], email: emails[1])
      fixture['expired_cookie'] = account_link_source_pair(user, "a11e-stand-#{ids[1]}").first
    end
    File.write(ARGV.fetch(0), JSON.generate(fixture))
    puts 'Rails account-link stand fixture: PASS three callback-issued anonymous pending sessions and expiry'
  end
when 'api_auth_otp_work'
  consume_api_otp_work(fixture)
when 'api_auth_password_work'
  consume_api_password_work(fixture)
when 'api_auth'
  consume_api_auth(fixture)
when 'account_link'
  consume_account_link(fixture, request)
when 'web_otp'
  consume_web_otp(fixture, request)
when 'api_two_factor_management'
  consume_api_two_factor_management(fixture)
when 'two_factor_management'
  consume_two_factor_management(fixture, request)
when 'account_update'
  consume_account_update(fixture, request)
else
  fixture.fetch('sessions').each do |name, entry|
    decrypted = jar(request, '_dawarich_session', entry.fetch('cookie')).encrypted['_dawarich_session']
    raise "Native #{name} session failed Rails decryption" unless decrypted == entry.fetch('expected')
  end

  remember = fixture.fetch('remember')
  verified = jar(request, 'remember_user_token', remember.fetch('cookie')).signed['remember_user_token']
  raise 'Native remember signing failed Rails verification' unless verified == remember.fetch('expected')

  ActionController::Base.allow_forgery_protection = true
  user = User.find(fixture.fetch('user_id'))
  user.update_columns(locked_at: nil, failed_attempts: 0,
                      remember_created_at: Time.iso8601(remember.fetch('created_at')))
  raise 'Synthetic oracle user password changed' unless user.valid_password?('safepassword12')

  form_client = native_client('_dawarich_session' => fixture.dig('sessions', 'form', 'cookie'))
  form_client.post('/users/sign_in', params: {
                     authenticity_token: fixture.fetch('form_token'),
                     user: { email: user.email, password: 'safepassword12' }
                   })
  unless form_client.response.status == 303
    env = form_client.request.env
    refusal = {
      status: form_client.response.status,
      invalid_password: form_client.response.body.include?('Invalid email or password.'),
      params: form_client.request.request_parameters.slice('user'),
      skip_storage: env['devise.skip_storage'],
      allow_params: env['devise.allow_params_authentication'],
      default_strategies: env['warden'].config[:default_strategies],
      failed_attempts: user.reload.failed_attempts, locked: user.access_locked?,
      received_session: form_client.request.cookie_jar.encrypted['_dawarich_session'],
      expected_session: fixture.dig('sessions', 'form', 'expected')
    }
    raise "Native form refused: #{JSON.generate(refusal)}"
  end

  session_client = native_client('_dawarich_session' => fixture.dig('sessions', 'login', 'cookie'))
  session_client.get('/stats')
  raise 'Native Warden session refused by Rails' unless session_client.response.status == 200

  remember_client = native_client('remember_user_token' => remember.fetch('cookie'))
  remember_client.get('/stats')
  raise 'Native remember credential refused by Rails' unless remember_client.response.status == 200

  csrf_token = remember_client.response.body[/name="csrf-token" content="([^"]+)"/, 1]
  remember_client.delete('/users/sign_out', params: { authenticity_token: csrf_token })
  raise 'Native remembered user logout failed' unless remember_client.response.status == 303

  replay = native_client('remember_user_token' => remember.fetch('cookie'))
  replay.get('/stats')
  raise 'Native remember replay survived Rails logout' unless replay.response.status == 302

  puts 'Native→Rails: 3 encrypted sessions, signed remember, actual CSRF login, Warden auth, ' \
       'remembered auth and global logout replay all accepted'

end
