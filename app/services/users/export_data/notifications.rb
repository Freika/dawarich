# frozen_string_literal: true

class Users::ExportData::Notifications
  def initialize(user)
    @user = user
  end

  def call
    # Export all notifications for the user
    user.notifications
        .as_json(except: %w[user_id id])
  end

  private

  attr_reader :user
end
