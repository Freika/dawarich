# frozen_string_literal: true

class UserAchievement < ApplicationRecord
  belongs_to :user

  validates :achievement_key, presence: true, uniqueness: { scope: :user_id }
  validates :earned_at, presence: true
end
