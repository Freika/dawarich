# frozen_string_literal: true

class FamilyMembership < ApplicationRecord
  belongs_to :family
  belongs_to :user

  validates :user_id, presence: true, uniqueness: true # One family per user
  validates :role, presence: true

  enum :role, { owner: 0, member: 1 }

  # Clear family cache when membership changes
  after_create :clear_family_cache
  after_update :clear_family_cache
  after_destroy :clear_family_cache

  private

  def clear_family_cache
    family&.clear_member_cache!
  end
end
