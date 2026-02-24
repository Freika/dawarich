# frozen_string_literal: true

class Users::ImportData::Settings
  def initialize(user, settings_data)
    @user = user
    @settings_data = settings_data
  end

  def call
    return false unless settings_data.is_a?(Hash)

    Rails.logger.info "Importing settings for user: #{user.email}"

    current_settings = user.settings || {}
    updated_settings = current_settings.merge(settings_data)

    user.update!(settings: updated_settings)

    Rails.logger.info 'Settings import completed'
    true
  end

  private

  attr_reader :user, :settings_data
end
