# frozen_string_literal: true

require_relative 'oracle_support'

RecoveryOracle.deterministic!('lifecycle-raw-')
NOW = RecoveryOracle::NOW
EMAIL = 'a11-recovery-oracle@dawarich.test'
FIELDS = %w[encrypted_password reset_password_token reset_password_sent_at failed_attempts locked_at unlock_token
            remember_created_at failed_otp_attempts otp_locked_at otp_required_for_login].freeze
DIRTY = {
  'immich_url' => 'https://immich.synthetic.test//', 'photoprism_url' => 'https://photos.synthetic.test/',
  'maps' => { 'url' => " https://tiles.synthetic.test/{z}/{x}/{y}.png\n", 'name' => 'Synthetic' },
  'route_opacity' => 0.6, 'fog_of_war_meters' => '50'
}.freeze
User.class_eval do
  def send_devise_notification(kind, *args)
    column = kind == :unlock_instructions ? 'unlock_token' : 'reset_password_token'
    RecoveryOracle.notifications << { kind:, raw: args.first, persisted_digest: reload.attributes[column] }
  end
end

def lifecycle_state(user) = RecoveryOracle.state(user, FIELDS)

def sanitized_request(name, kind, settings, locked: false)
  user = RecoveryOracle.fresh_user(EMAIL)
  user.update_columns(settings:, locked_at: locked ? NOW : nil, failed_attempts: locked ? 10 : 0)
  delivered = RecoveryOracle.notifications.size
  row = { name:, kind:, locked:, settings_before: settings }
  begin
    if kind == 'reset'
      User.send_reset_password_instructions(email: EMAIL)
    else
      User.send_unlock_instructions(email: EMAIL)
    end
  rescue StandardError => e
    row[:raised] = e.class.name
  end
  user.reload
  row.merge(
    settings_after: user.settings, notified: RecoveryOracle.notifications[delivered..].map { _1[:kind] },
    token_issued: !(kind == 'reset' ? user.reset_password_token : user.unlock_token).nil?
  )
end

result = { reset_boundaries: [], resets: [], unlocks: [] }
user = RecoveryOracle.fresh_user(EMAIL)
[nil, NOW - 21_600 - 0.000001, NOW - 21_600, NOW + 60].each do |sent|
  user.reset_password_sent_at = sent
  result[:reset_boundaries] << { sent_at: sent&.iso8601(6), now: NOW.iso8601(6),
                                  valid: user.reset_password_period_valid? }
end
RESET_CASES = [
  %w[short short], %w[newpassword12345 different], ['newpassword12345', nil], ['a' * 100, 'a' * 100],
  ["a#{769.chr(Encoding::UTF_8)}" * 6, nil], [('a' * 71) + 128_512.chr(Encoding::UTF_8), nil]
].freeze
RESET_CASES.each do |password, confirmation|
  user = RecoveryOracle.fresh_user(EMAIL)
  raw = user.send_reset_password_instructions
  user.update_columns(failed_attempts: 11, locked_at: NOW - 30, unlock_token: 'existing', failed_otp_attempts: 10,
                      otp_locked_at: NOW - 10, remember_created_at: NOW - 60)
  before = lifecycle_state(user)
  reset = User.reset_password_by_token(reset_password_token: raw, password:, password_confirmation: confirmation)
  model = lifecycle_state(user)
  reset.unlock_access! if reset.errors.empty?
  result[:resets] << { password:, confirmation:, before:, model_after: model,
                       controller_unlock_after: lifecycle_state(user), errors: reset.errors.details,
                       valid_password: user.reload.valid_password?(password) }
end
user = RecoveryOracle.fresh_user(EMAIL)
user.update_columns(failed_attempts: 9)
user.lock_access!
first = RecoveryOracle.notifications.last
before = lifecycle_state(user)
raw = user.resend_unlock_instructions
second = RecoveryOracle.notifications.last
unlocked = User.unlock_access_by_token(raw)
result[:unlocks] << { before:, first:, second:, after: lifecycle_state(user), errors: unlocked.errors.details,
                      replay_errors: User.unlock_access_by_token(raw).errors.details }
result[:sanitized_requests] = [
  sanitized_request('reset_dirty', 'reset', DIRTY),
  sanitized_request('unlock_locked_dirty', 'unlock', DIRTY, locked: true),
  sanitized_request('unlock_unlocked_dirty', 'unlock', DIRTY),
  sanitized_request('reset_maps_string', 'reset', { 'maps' => 'some url', 'photoprism_url' => '///' }),
  sanitized_request('reset_maps_boolean', 'reset', { 'maps' => true }),
  sanitized_request('reset_settings_array', 'reset', ['legacy']),
  sanitized_request('reset_immich_integer', 'reset', { 'immich_url' => 5 }),
  sanitized_request('unlock_maps_array', 'unlock', { 'maps' => ['x'] }, locked: true),
  sanitized_request('unlock_unlocked_maps_array', 'unlock', { 'maps' => ['x'] }),
  sanitized_request('reset_maps_url_integer', 'reset', { 'maps' => { 'url' => 7 } })
]
user = RecoveryOracle.fresh_user(EMAIL)
input = JSON.parse(File.read(File.expand_path('../../../fixtures/auth/recovery/phoenix_hashes.json', __dir__)))
result[:phoenix_hashes] = input.map do |row|
  user.update_columns(encrypted_password: row.fetch('hash'))
  row.merge('rails_valid_password' => user.reload.valid_password?(row.fetch('password')))
end
result[:notifications] = RecoveryOracle.notifications.map do |row|
  row.merge(persisted_digest: RecoveryOracle.halves(row[:persisted_digest]))
end

RecoveryOracle.write(ARGV.fetch(0), result)
puts 'Captured the Rails recovery model oracle; no SMTP'
