# frozen_string_literal: true

require_relative 'oracle_support'

ActionController::Base.allow_forgery_protection = true
Rails.application.env_config['action_dispatch.show_exceptions'] = :all
User.class_eval do
  def send_devise_notification(*)
    raise 'synthetic delivery owner failure'
  end
end

def recovery_session
  ActionDispatch::Integration::Session.new(Rails.application).tap { |session| session.host!('www.example.com') }
end

email = 'recovery-effects-oracle@dawarich.test'
user = RecoveryOracle.fresh_user(email)
result = {}
{ missing: nil, invalid: 'bad' }.each do |kind, token|
  session = recovery_session
  session.post('/users/password', params: { authenticity_token: token, user: { email: } })
  result[kind] = { status: session.response.status, token_after: user.reload.reset_password_token }
end
session = recovery_session
session.get('/users/password/new')
token = session.response.body[/name="csrf-token" content="([^"]+)"/, 1] || raise('source CSRF token absent')
session.post('/users/password', params: { authenticity_token: token, user: { email: } },
                                headers: { 'Origin' => 'http://foreign.test' })
result[:foreign_origin] = { status: session.response.status, token_after: user.reload.reset_password_token }
session.post('/users/password', params: { authenticity_token: token, user: { email: } })
result[:delivery_failure] = {
  status: session.response.status, digest_persisted: user.reload.reset_password_token.present?,
  sent_at_persisted: user.reset_password_sent_at.present?
}

RecoveryOracle.write(ARGV.fetch(0), result)
puts 'Captured recovery CSRF and notification-failure effects without delivery'
