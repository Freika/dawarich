# frozen_string_literal: true

require 'json'
require 'time'
require 'stringio'
require 'uri'
require 'active_support/testing/time_helpers'

raise 'A11 own test DB required' unless Rails.env.test? && ENV.fetch('DATABASE_NAME').start_with?('dawarich_test_a11')

ActiveJob::Base.queue_adapter = :test
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = false
fixture = JSON.parse(File.read(ARGV.fetch(0)))
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

if ARGV[1] == 'two_factor_management'
  consume_two_factor_management(fixture, request)
elsif ARGV[1] == 'account_update'
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
