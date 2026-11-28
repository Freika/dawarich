# frozen_string_literal: true

class Users::ImportData::Settings
  def initialize(user, settings_data)
    @user = user
    @settings_data = settings_data
  end

  def call
    return false unless settings_data.is_a?(Hash)

    Rails.logger.info "Importing settings for user #{user.id}"

    current_settings = user.settings || {}
    updated_settings = current_settings.merge(importable_settings)

    user.update!(settings: updated_settings)

    Rails.logger.info 'Settings import completed'
    true
  end

  private

  attr_reader :user, :settings_data

  # An archive never changes the account's integration connections. Importing
  # a URL without its secret would point a stored key at the archive's host, or
  # leave a connection that fails on every scheduled sync.
  def importable_settings
    settings_data.reject { |key, _value| Users::IntegrationSettingKeys.connection_key?(key) }
  end
end
