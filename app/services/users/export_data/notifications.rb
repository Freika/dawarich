# frozen_string_literal: true

class Users::ExportData::Notifications
  # System-generated notification titles that should not be exported
  SYSTEM_NOTIFICATION_TITLES = [
    'Data import completed',
    'Data import failed',
    'Export completed',
    'Export failed'
  ].freeze

  def initialize(user)
    @user = user
  end

  def call
    # Export only user-generated notifications, not system-generated ones
    user.notifications
        .where.not(title: SYSTEM_NOTIFICATION_TITLES)
        .as_json(except: %w[user_id id])
  end

  private

  attr_reader :user
end
