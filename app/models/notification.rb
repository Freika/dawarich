# frozen_string_literal: true

class Notification < ApplicationRecord
  after_create_commit :broadcast_notification

  belongs_to :user

  validates :title, :content, :kind, presence: true

  enum :kind, { info: 0, warning: 1, error: 2 }

  scope :unread, -> { where(read_at: nil) }

  def read?
    read_at.present?
  end

  private

  def broadcast_notification
    NotificationsChannel.broadcast_to(
      user,
      {
        # id: id,
        # title: title,
        # content: content,
        # kind: kind,
        # timestamp: Time.current.to_i
      }
    )
  end
end
