# frozen_string_literal: true

require 'json'
require 'time'
require 'stringio'
require 'uri'
require 'active_support/testing/time_helpers'

mode = ARGV[1]
database_allowed = ENV.fetch('DATABASE_NAME').start_with?('dawarich_test')
raise 'Protocol own test DB required' unless Rails.env.test? && database_allowed

ActiveJob::Base.queue_adapter = :test
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = false
fixture = JSON.parse(File.read(ARGV.fetch(0)))
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
