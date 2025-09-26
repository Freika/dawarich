# frozen_string_literal: true

class FamilyMembership < ApplicationRecord
  belongs_to :family
  belongs_to :user

  validates :user_id, presence: true, uniqueness: true # One family per user
  validates :role, presence: true

  enum :role, { owner: 0, member: 1 }
end
