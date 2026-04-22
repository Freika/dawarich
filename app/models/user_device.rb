# frozen_string_literal: true

class UserDevice < ApplicationRecord
  belongs_to :user

  enum :platform, { ios: 0, android: 1 }, prefix: :platform

  validates :platform, :device_id, presence: true
  validates :device_id, uniqueness: { scope: :user_id }
end
