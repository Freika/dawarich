# frozen_string_literal: true

class Family < ApplicationRecord
  has_many :family_memberships, dependent: :destroy
  has_many :members, through: :family_memberships, source: :user
  has_many :family_invitations, dependent: :destroy
  belongs_to :creator, class_name: 'User'

  validates :name, presence: true, length: { maximum: 50 }

  MAX_MEMBERS = 5

  def can_add_members?
    members.count < MAX_MEMBERS
  end
end
