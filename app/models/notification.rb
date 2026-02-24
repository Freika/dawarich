# frozen_string_literal: true

class Notification < ApplicationRecord
  after_create_commit :broadcast_notification

  belongs_to :user

  validates :title, :content, :kind, presence: true

  enum :kind, { info: 0, warning: 1, error: 2 }

  scope :unread, -> { where(read_at: nil).order(created_at: :desc) }

  def read?
    read_at.present?
  end

  private

  def broadcast_notification
    broadcast_prepend_to(
      [user, :notifications],
      target: 'notifications-list',
      partial: 'notifications/navbar_item',
      locals: { notification: self }
    )

    broadcast_replace_to(
      [user, :notifications],
      target: 'notifications-badge',
      partial: 'notifications/badge',
      locals: { count: user.notifications.unread.count }
    )
  end
end
