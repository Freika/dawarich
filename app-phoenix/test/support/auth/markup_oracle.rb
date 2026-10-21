# frozen_string_literal: true

require_relative 'recovery/oracle_support'

RecoveryOracle.deterministic!('markup-')
User.class_eval do
  def send_devise_notification(kind, *args)
    RecoveryOracle.notifications << { kind:, raw: args.first }
  end
end

EMAIL = 'markup-oracle@dawarich.test'
HERO = '<div class="hero min-h-content bg-base-200">'
TOAST = '<div class="fixed top-5 right-5 flex flex-col gap-2 z-50" id="flash-messages">'

def new_session
  ActionDispatch::Integration::Session.new(Rails.application).tap { |session| session.host!('www.example.com') }
end

def raw_div(body, marker)
  start = body.index(marker) || raise("markup absent: #{marker}")
  depth = 0
  body.to_enum(:scan, %r{<(/?)div\b}).each do
    match = Regexp.last_match
    next if match.begin(0) < start

    depth += match[1].empty? ? 1 : -1
    return body[start..body.index('>', match.begin(0))] if depth.zero?
  end
  raise "unbalanced markup: #{marker}"
end

def row(session, issued: nil, **extra)
  body = session.response.body
  toast = raw_div(body, TOAST)
  html = raw_div(body, HERO).gsub(/(name="authenticity_token" value=")[^"]*"/, '\1CSRF"')
  html = html.gsub(issued, 'synthetic') if issued
  { status: session.response.status, html:, toast: toast.include?('role="alert"') ? toast : nil }.merge(extra)
end

def csrf(session)
  session.response.body[/name="csrf-token" content="([^"]+)"/, 1] || raise('source CSRF token absent')
end

ActionController::Base.allow_forgery_protection = true
user = RecoveryOracle.fresh_user(EMAIL)
signin = {}
[['signin', false, nil], ['signin_registration', true, nil], ['signin_de', false, 'de'],
 ['signin_fr', false, 'fr']].each do |name, registration, locale|
  DawarichSettings.set_registration_enabled(registration)
  session = new_session
  session.get('/users/sign_in', params: { locale: }) if locale
  session.get('/users/sign_in')
  signin[name] = row(session, registration:, locale: locale || 'en')
end
DawarichSettings.set_registration_enabled(false)
session = new_session
session.get('/users/sign_in')
session.post('/users/sign_in', params: { authenticity_token: csrf(session),
                                         user: { email: user.email, password: 'not-the-password', remember_me: '0' } })
signin['signin_failed'] = row(session, registration: false, locale: 'en', email: user.email)
DawarichSettings.set_registration_enabled(false)

recovery = {}
{ password_new: '/users/password/new', password_edit: '/users/password/edit?reset_password_token=synthetic',
  unlock_new: '/users/unlock/new', unlock_invalid: '/users/unlock?unlock_token=unknown' }.each do |name, path|
  session = new_session
  session.get(path)
  recovery[name] = row(session, registration: false, token: path[/token=(\w+)/, 1])
end
[%i[password_new_registration /users/password/new], %i[unlock_new_registration /users/unlock/new]]
  .each do |name, path|
  DawarichSettings.set_registration_enabled(true)
  session = new_session
  session.get(path.to_s)
  recovery[name] = row(session, registration: true)
end
DawarichSettings.set_registration_enabled(false)
user = RecoveryOracle.fresh_user(EMAIL)
raw = user.send_reset_password_instructions
{ password_edit_errors: [raw, 'short', 'different'], password_edit_invalid: ['unknown', 'newpassword12345', nil],
  password_edit_blank_token: ['', 'newpassword12345', nil], password_edit_expired: [raw, 'newpassword12345', nil] }
  .each do |name, (token, password, confirmation)|
  user.update_columns(reset_password_sent_at: name == :password_edit_expired ? 7.hours.ago : Time.now.utc)
  session = new_session
  session.get('/users/password/edit?reset_password_token=synthetic')
  session.put('/users/password', params: { authenticity_token: csrf(session), user: {
                reset_password_token: token, password:, password_confirmation: confirmation
              } })
  recovery[name] = row(session, issued: raw, registration: false, token: token == raw ? 'synthetic' : token)
end

RecoveryOracle.write(ARGV.fetch(0), { rails_version: Rails.version, signin:, recovery: })
puts 'Captured the raw markup of every native auth page; delivery disabled'
