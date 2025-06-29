# frozen_string_literal: true

class Users::ImportData::Notifications
  def initialize(user, notifications_data)
    @user = user
    @notifications_data = notifications_data
  end

  def call
    return 0 unless notifications_data.is_a?(Array)

    Rails.logger.info "Importing #{notifications_data.size} notifications for user: #{user.email}"

    notifications_created = 0

    notifications_data.each do |notification_data|
      next unless notification_data.is_a?(Hash)

      # Check if notification already exists (match by title, content, and created_at)
      existing_notification = user.notifications.find_by(
        title: notification_data['title'],
        content: notification_data['content'],
        created_at: notification_data['created_at']
      )

      if existing_notification
        Rails.logger.debug "Notification already exists: #{notification_data['title']}"
        next
      end

      # Create new notification
      notification_attributes = notification_data.except('created_at', 'updated_at')
      notification = user.notifications.create!(notification_attributes)
      notifications_created += 1

      Rails.logger.debug "Created notification: #{notification.title}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Failed to create notification: #{e.message}"
      next
    end

    Rails.logger.info "Notifications import completed. Created: #{notifications_created}"
    notifications_created
  end

  private

  attr_reader :user, :notifications_data
end
