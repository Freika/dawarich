# frozen_string_literal: true

class Notification < ApplicationRecord
  after_create_commit :broadcast_notification
  after_update_commit :broadcast_notification_update
  after_destroy_commit :broadcast_notification_removal

  belongs_to :user

  validates :title, :content, :kind, presence: true

  enum :kind, { info: 0, warning: 1, error: 2 }

  scope :unread, -> { where(read_at: nil).order(created_at: :desc) }

  def read?
    read_at.present?
  end

  def update_with_broadcast!(attributes)
    update!(attributes)
  end

  def self.broadcast_badge_for(user)
    Turbo::StreamsChannel.broadcast_replace_to(
      [user, :notifications], target: 'notifications-badge',
      partial: 'notifications/badge', locals: { count: user.notifications.unread.count }
    )
  end

  def self.broadcast_read_all_for(user)
    broadcast_badge_for(user)
    Turbo::StreamsChannel.broadcast_remove_to([user, :notifications], targets: '.notification-item')
    broadcast_page_refresh_for(user)
  end

  # Targets every list, detail and navbar copy without refreshing other tabs.
  def self.broadcast_delete_all_for(user)
    broadcast_badge_for(user)
    Turbo::StreamsChannel.broadcast_remove_to(
      [user, :notifications],
      targets: '.notification-item, [id^="notification_"], [id^="detail_notification_"]'
    )
    broadcast_page_refresh_for(user)
  end

  # Only the notification pages subscribe to this stream: a refresh on the navbar
  # stream would reload every open tab, including maps.
  def self.broadcast_page_refresh_for(user)
    Turbo::StreamsChannel.broadcast_refresh_to([user, :notification_pages])
  end

  private

  def broadcast_notification_update
    self.class.broadcast_badge_for(user)
    if read?
      broadcast_remove_to([user, :notifications], target: "navbar_notification_#{id}")
    else
      broadcast_prepend_to([user, :notifications], target: 'notifications-list',
                                                  partial: 'notifications/navbar_item', locals: { notification: self })
    end
    [false, true].each do |show_content|
      target = show_content ? "detail_notification_#{id}" : "notification_#{id}"
      broadcast_replace_to([user, :notifications], target: target, partial: 'notifications/notification',
                                                  locals: { notification: self, show_content: show_content })
    end
  end

  def broadcast_notification_removal
    %W[notification_#{id} detail_notification_#{id} navbar_notification_#{id}].each do |target|
      broadcast_remove_to([user, :notifications], target: target)
    end
    self.class.broadcast_badge_for(user)
  end

  def broadcast_notification
    broadcast_prepend_to(
      [user, :notifications],
      target: 'notifications-list',
      partial: 'notifications/navbar_item',
      locals: { notification: self }
    )

    self.class.broadcast_badge_for(user)
  end
end
