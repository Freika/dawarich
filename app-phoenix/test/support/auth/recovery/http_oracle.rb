# frozen_string_literal: true

secret = 'phoenix-a2-cookie-fixture-secret-not-for-production'
Rails.application.config.secret_key_base = secret
Rails.application.env_config['action_dispatch.secret_key_base'] = secret
Rails.application.env_config['action_dispatch.key_generator'] = Rails.application.key_generator
Devise.secret_key = secret
require_relative 'oracle_support'

RecoveryOracle.deterministic!('http-raw-')
User.before_validation(on: :create) { self.id ||= 20_115_301 if email == 'recovery-http-oracle@dawarich.test' }
User.class_eval do
  def send_devise_notification(kind, *args)
    RecoveryOracle.notifications << { kind:, raw: args.first }
  end
end

EMAIL = 'recovery-http-oracle@dawarich.test'
DIRTY = {
  'immich_url' => 'https://immich.synthetic.test//', 'maps' => { 'url' => " https://tiles.synthetic.test\n" }
}.freeze

def recovery_session
  ActionDispatch::Integration::Session.new(Rails.application).tap { |session| session.host!('www.example.com') }
end

def recovery_response(session)
  cookies = { '_dawarich_session' => session.cookies['_dawarich_session'] }
  data = ActionDispatch::Cookies::CookieJar.build(session.request, cookies).encrypted['_dawarich_session'] || {}
  { status: session.response.status, location: session.response.headers['Location'],
    signed_in: data.key?('warden.user.user.key'), flash: data['flash'], csrf_present: data.key?('_csrf_token') }
end

result = {}
user = RecoveryOracle.fresh_user(EMAIL)
session = recovery_session
session.get('/users/password/edit')
result[:missing_token_edit] = recovery_response(session)
session = recovery_session
session.post('/users/password', params: { user: { email: user.email } })
result[:known_request] = recovery_response(session)
session = recovery_session
session.post('/users/password', params: { user: { email: 'unknown@dawarich.test' } })
result[:unknown_request] = recovery_response(session)
user = RecoveryOracle.fresh_user(EMAIL)
user.update_columns(settings: DIRTY)
session = recovery_session
session.post('/users/password', params: { user: { email: user.email } })
result[:dirty_settings_request] = recovery_response(session).merge(settings_before: DIRTY,
                                                                   settings: user.reload.settings)
session = recovery_session
session.put('/users/password', params: { user: { reset_password_token: 'unknown', password: 'newpassword12345',
                                                 password_confirmation: 'newpassword12345' } })
result[:unknown_reset] = recovery_response(session)
[false, true].each do |otp|
  user = RecoveryOracle.fresh_user(EMAIL)
  user.update_columns(otp_required_for_login: otp, failed_otp_attempts: 10, otp_locked_at: Time.current,
                      failed_attempts: 11, locked_at: Time.current, unlock_token: 'old')
  raw = user.send_reset_password_instructions
  session = recovery_session
  session.put('/users/password', params: { user: { reset_password_token: raw, password: 'newpassword12345',
                                                   password_confirmation: 'newpassword12345' } })
  state = user.reload.attributes.slice('failed_attempts', 'locked_at', 'unlock_token', 'failed_otp_attempts',
                                       'otp_locked_at', 'sign_in_count', 'reset_password_token')
  result[otp ? :otp_success_reset : :success_reset] = recovery_response(session).merge(state:)
end
user = RecoveryOracle.fresh_user(EMAIL)
user.lock_access!
raw = RecoveryOracle.notifications.last[:raw]
session = recovery_session
session.get('/users/unlock', params: { unlock_token: raw })
result[:success_unlock] = recovery_response(session)
session = recovery_session
session.get('/users/unlock', params: { unlock_token: raw })
result[:replay_unlock] = recovery_response(session)
user = RecoveryOracle.fresh_user(EMAIL)
user.lock_access!
session = recovery_session
session.post('/users/unlock', params: { user: { email: user.email } })
result[:locked_unlock_request] = recovery_response(session)
user.unlock_access!
session = recovery_session
session.post('/users/unlock', params: { user: { email: user.email } })
result[:unlocked_unlock_request] = recovery_response(session)
session = recovery_session
session.post('/users/unlock', params: { user: { email: 'unknown@dawarich.test' } })
result[:unknown_unlock_request] = recovery_response(session)

user = RecoveryOracle.fresh_user(EMAIL)
raw = user.send_reset_password_instructions
user.update_columns(reset_password_sent_at: RecoveryOracle::NOW - 21_600 - 1)
session = recovery_session
session.patch('/users/password', params: { user: { reset_password_token: raw, password: 'newpassword12345',
                                                  password_confirmation: 'newpassword12345' } })
result[:expired_patch_reset] =
  recovery_response(session).merge(token_retained: user.reload.reset_password_token.present?)

user.update_columns(reset_password_sent_at: RecoveryOracle::NOW - 21_600)
session = recovery_session
session.patch('/users/password', params: { user: { reset_password_token: raw, password: 'newpassword12345',
                                                  password_confirmation: 'newpassword12345' } })
result[:boundary_patch_reset] = recovery_response(session).merge(token_cleared: user.reload.reset_password_token.nil?)

RecoveryOracle.write(ARGV.fetch(0), result)
puts 'Captured Rails recovery HTTP responses; delivery disabled'
