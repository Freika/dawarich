# frozen_string_literal: true

module PhoenixAppVersion
  module_function

  def fresh_latest
    connection = ActiveRecord::Base.connection
    return unless connection.select_value("SELECT to_regclass('phoenix.app_version') IS NOT NULL")

    connection.select_value(
      "SELECT latest_version FROM phoenix.app_version WHERE checked_at > now() - interval '6 hours'"
    )
  end
end
