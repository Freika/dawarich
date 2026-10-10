# frozen_string_literal: true

module PhoenixRegistrationSetting
  class IncompleteUpgrade < StandardError; end

  module_function

  def fetch(default = ALLOW_EMAIL_PASSWORD_REGISTRATION)
    return Rails.cache.fetch('dawarich/registration_enabled') { default } unless table?

    rows = connection.exec_query(
      'SELECT enabled FROM phoenix.registration_setting WHERE id = true', 'PhoenixRegistrationSetting'
    ).rows
    raise IncompleteUpgrade, 'registration copy incomplete' if rows.empty?

    rows.first.first
  end

  def put(enabled)
    return Rails.cache.write('dawarich/registration_enabled', enabled) unless table?

    updated = connection.exec_update(
      'UPDATE phoenix.registration_setting SET enabled = $1, updated_at = statement_timestamp() WHERE id = true',
      'PhoenixRegistrationSetting', [enabled]
    )
    raise IncompleteUpgrade, 'registration copy incomplete' unless updated == 1

    true
  end

  def table? = PhoenixSchema.table?('registration_setting')

  def connection = ActiveRecord::Base.connection

  private_class_method :table?, :connection
end
