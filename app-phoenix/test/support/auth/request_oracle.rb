# frozen_string_literal: true

require 'json'
require 'time'

unless Rails.env.test? && ENV.fetch('DATABASE_NAME').start_with?('dawarich_test_a11')
  raise 'A11 oracle requires its own test database'
end

ActiveJob::Base.queue_adapter = :test
ActionMailer::Base.delivery_method = :test
ActionMailer::Base.perform_deliveries = false

FIELDS = %w[id encrypted_password failed_attempts locked_at unlock_token remember_created_at
            sign_in_count current_sign_in_at last_sign_in_at current_sign_in_ip last_sign_in_ip].freeze

def state(user)
  attributes = user.reload.attributes.slice(*FIELDS)
  attributes['unlock_token'] &&= '[issued]'
  attributes.transform_values { |value| value.respond_to?(:iso8601) ? value.utc.iso8601(6) : value }
end

def masked_parts(masked)
  bytes = Base64.urlsafe_decode64(masked)
  { one_time_pad: bytes[0, 32].unpack1('H*'), xored: bytes[32, 32].unpack1('H*') }
end

def client(cookies = {})
  ActionDispatch::Integration::Session.new(Rails.application).tap do |session|
    session.host!('www.example.com')
    cookies.each { |name, value| session.cookies[name] = value }
  end
end

def decoded(session)
  cookies = %w[_dawarich_session remember_user_token].index_with { |name| session.cookies[name] }.compact
  jar = ActionDispatch::Cookies::CookieJar.build(session.request, cookies)
  { session: jar.encrypted['_dawarich_session'], remember: jar.signed['remember_user_token'] }
end

def response(session)
  {
    status: session.response.status,
    location: session.response.headers['Location'],
    set_cookie: Array(session.response.headers['Set-Cookie']),
    invalid_message: session.response.body.include?('Invalid email or password.'),
    signed_out_message: session.response.body.include?('Signed out successfully.')
  }
end

def login(session, email, password, remember: false)
  session.post('/users/sign_in', params: {
                 user: { email: email, password: password, remember_me: remember ? '1' : '0' }
               }, headers: { 'REMOTE_ADDR' => '192.0.2.10' })
end

email = 'a11-credentials-oracle@dawarich.test'
User.unscoped.where(email: email).delete_all
user = User.new(email: email, password: 'safepassword12', status: :active,
                active_until: Time.utc(2099, 1, 1))
user.skip_auto_trial = true
user.skip_family_sync = true
user.save!

result = {
  rails_version: Rails.version,
  devise_version: Gem.loaded_specs.fetch('devise').version.to_s,
  ruby_version: RUBY_VERSION,
  paranoid: Devise.paranoid,
  user_before: state(user)
}

session = client
session.get('/users/sign_in')
raise "sign-in GET failed: #{session.response.status}" unless session.response.status == 200

result[:guest] = { response: response(session), decoded: decoded(session) }
login(session, "  #{email.upcase}  ", 'safepassword12', remember: true)
raise "login failed: #{session.response.status}" unless session.response.redirect?

result[:login] = { response: response(session), decoded: decoded(session), user: state(user) }

captured_session = session.cookies['_dawarich_session']
captured_remember = session.cookies['remember_user_token']
raise 'remember cookie was not issued' if captured_remember.blank?

remember_device = client('remember_user_token' => captured_remember)
remember_device.get('/stats')
result[:remember_restore] = {
  response: response(remember_device), decoded: decoded(remember_device), user: state(user)
}

session.delete('/users/sign_out')
result[:logout] = { response: response(session), decoded: decoded(session), user: state(user) }

remember_replay = client('remember_user_token' => captured_remember)
remember_replay.get('/stats')
result[:remember_replay_after_logout] = { response: response(remember_replay), user: state(user) }

session_replay = client('_dawarich_session' => captured_session)
session_replay.get('/stats')
result[:session_replay_after_logout] = { response: response(session_replay), user: state(user) }

wrong = client
login(wrong, email, 'not-the-password')
result[:wrong_password] = { response: response(wrong), user: state(user) }
unknown = client
login(unknown, 'a11-unknown@dawarich.test', 'not-the-password')
result[:unknown_email] = { response: response(unknown), user: state(user) }

blank = client
login(blank, email, '')
result[:blank_password] = { response: response(blank), user: state(user) }

user.update_columns(failed_attempts: 9)
correct_at_threshold = client
login(correct_at_threshold, email, 'safepassword12')
result[:correct_password_at_nine] = { response: response(correct_at_threshold), user: state(user) }

user.update_columns(failed_attempts: 9, locked_at: nil, unlock_token: nil)
last_failure = client
login(last_failure, email, 'not-the-password')
result[:lock_threshold] = { response: response(last_failure), user: state(user) }
locked_correct = client
login(locked_correct, email, 'safepassword12')
result[:locked_correct_password] = { response: response(locked_correct), user: state(user) }

user.update_columns(locked_at: 2.hours.ago, failed_attempts: 10)
expired_wrong = client
login(expired_wrong, email, 'not-the-password')
result[:expired_lock_wrong_password] = { response: response(expired_wrong), user: state(user) }

ActionController::Base.allow_forgery_protection = true
csrf = client
csrf.get('/users/sign_in')
document = Nokogiri::HTML(csrf.response.body)
masked = document.at_css('input[name="authenticity_token"]')['value']
meta = document.at_css('meta[name="csrf-token"]')['content']
result[:csrf_guest] = {
  response: response(csrf), decoded: decoded(csrf), form_token: masked_parts(masked), meta_token: masked_parts(meta)
}
csrf.post('/users/sign_in', params: {
            authenticity_token: masked, user: { email: email, password: 'safepassword12' }
          })
result[:csrf_login] = { response: response(csrf), decoded: decoded(csrf), user: state(user) }
invalid_csrf = client
invalid_csrf.get('/users/sign_in')
invalid_csrf.post('/users/sign_in', params: {
                    authenticity_token: 'invalid', user: { email: email, password: 'safepassword12' }
                  })
result[:invalid_csrf] = { response: response(invalid_csrf), user: state(user) }

ActionController::Base.allow_forgery_protection = false
{
  otp_wrong_password: [{ otp_required_for_login: true }, 'not-the-password'],
  otp_blank_password: [{ otp_required_for_login: true }, ''],
  oauth_wrong_password: [{ provider: 'github', uid: 'a11-oracle' }, 'not-the-password'],
  pending_payment_wrong_password: [{ status: 3 }, 'not-the-password']
}.each do |name, (columns, password)|
  user.update_columns(failed_attempts: 0, locked_at: nil, unlock_token: nil, otp_required_for_login: false,
                      provider: nil, uid: nil, status: 1)
  user.update_columns(columns)
  attempt = client
  login(attempt, email, password)
  result[name] = { setup: columns, response: response(attempt), user: state(user) }
end

File.write(ARGV.fetch(0), "#{JSON.pretty_generate(result)}\n")
puts "Captured A11 request oracle: #{result.keys.size - 5} bounded cases; test delivery only"
