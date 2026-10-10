# frozen_string_literal: true

require_relative 'oracle_support'

User.class_eval { def send_devise_notification(*); end }

def recovery_error_row(locale, view, kind, resource)
  heading = I18n.t('errors.messages.not_saved', count: resource.errors.count,
                                                resource: User.model_name.human.downcase)
  { locale:, view:, kind:, errors: resource.errors.details, messages: resource.errors.full_messages, heading: }
end

user = RecoveryOracle.fresh_user('recovery-errors-oracle@dawarich.test')
raw = user.send_reset_password_instructions
cases = [
  [:invalid, 'unknown', 'newpassword12345', 'newpassword12345'],
  [:blank_token, '', 'newpassword12345', 'newpassword12345'],
  [:too_short, raw, 'short', 'short'],
  [:too_long, raw, 'a' * 129, 'a' * 129],
  [:confirmation, raw, 'newpassword12345', 'different'],
  [:blank, raw, nil, nil],
  [:short_mismatch, raw, 'short', 'different'],
  [:expired, raw, 'newpassword12345', 'newpassword12345']
]
rows = []
%w[en de fr].each do |locale|
  I18n.with_locale(locale) do
    cases.each do |kind, token, password, confirmation|
      user.update_columns(reset_password_sent_at: kind == :expired ? 7.hours.ago : Time.now.utc)
      result = User.reset_password_by_token(reset_password_token: token, password:,
                                            password_confirmation: confirmation)
      rows << recovery_error_row(locale, 'password_edit', kind, result)
    end
    rows << recovery_error_row(locale, 'unlock_new', 'invalid', User.unlock_access_by_token('unknown'))
  end
end

RecoveryOracle.write(ARGV.fetch(0), rows)
puts "Captured #{rows.size} recovery validation messages without delivery"
