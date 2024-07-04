# frozen_string_literal: true

class Notification < ApplicationRecord
  belongs_to :user

  validates :title, :content, :kind, presence: true

  enum kind: { info: 0, warning: 1, error: 2 }

  scope :unread, -> { where(read_at: nil) }
end
