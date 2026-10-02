# frozen_string_literal: true

require 'json'
require 'time'
require 'stringio'
require 'uri'

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

fixture.fetch('sessions').each do |name, entry|
  decrypted = jar(request, '_dawarich_session', entry.fetch('cookie')).encrypted['_dawarich_session']
  raise "Native #{name} session failed Rails decryption" unless decrypted == entry.fetch('expected')
end

remember = fixture.fetch('remember')
verified = jar(request, 'remember_user_token', remember.fetch('cookie')).signed['remember_user_token']
raise 'Native remember signing failed Rails verification' unless verified == remember.fetch('expected')

def native_client(cookies)
  ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
    session.host!('www.example.com')
    cookies.each { |name, value| session.cookies[name] = URI.decode_www_form_component(value) }
  end
end

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
