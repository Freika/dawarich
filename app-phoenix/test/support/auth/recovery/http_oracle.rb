# frozen_string_literal: true

require 'nokogiri'
require_relative 'oracle_support'

RecoveryOracle.deterministic!('http-raw-')
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

def recovery_markup(session)
  card = Nokogiri::HTML(session.response.body).at_css('div.hero')
  card.css('input[name="authenticity_token"]').each { |input| input['value'] = 'CSRF' }
  { status: session.response.status, registration: card.to_html.include?('/users/sign_up'), html: card.to_html }
end

def csrf(session)
  session.response.body[/name="csrf-token" content="([^"]+)"/, 1] || raise('source CSRF token absent')
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

ActionController::Base.allow_forgery_protection = true
markup = {}
{ password_new: '/users/password/new', password_edit: '/users/password/edit?reset_password_token=synthetic',
  unlock_new: '/users/unlock/new', unlock_invalid: '/users/unlock?unlock_token=unknown' }.each do |name, path|
  session = recovery_session
  session.get(path)
  markup[name] = recovery_markup(session)
end
user = RecoveryOracle.fresh_user(EMAIL)
raw = user.send_reset_password_instructions
{ password_edit_errors: [raw, 'short', 'different'], password_edit_invalid: ['unknown', 'newpassword12345', nil],
  password_edit_blank_token: ['', 'newpassword12345', nil], password_edit_expired: [raw, 'newpassword12345', nil] }
  .each do |name, (token, password, confirmation)|
  user.update_columns(reset_password_sent_at: name == :password_edit_expired ? 7.hours.ago : Time.now.utc)
  session = recovery_session
  session.get('/users/password/edit?reset_password_token=synthetic')
  session.put('/users/password', params: { authenticity_token: csrf(session), user: {
                reset_password_token: token, password:, password_confirmation: confirmation
              } })
  markup[name] = recovery_markup(session).merge(token:)
end
result[:markup] = markup

RecoveryOracle.write(ARGV.fetch(0), result)
puts 'Captured Rails recovery HTTP responses and form markup; delivery disabled'
