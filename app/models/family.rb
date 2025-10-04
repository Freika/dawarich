# frozen_string_literal: true

class Family < ApplicationRecord
  has_many :family_memberships, dependent: :destroy
  has_many :members, through: :family_memberships, source: :user
  has_many :family_invitations, dependent: :destroy
  belongs_to :creator, class_name: 'User'

  validates :name, presence: true, length: { maximum: 50 }

  MAX_MEMBERS = 5

  scope :with_members, -> { includes(:members, :family_memberships) }
  scope :with_pending_invitations, -> { includes(family_invitations: :invited_by) }

  def can_add_members?
    (member_count + pending_invitations_count) < MAX_MEMBERS
  end

  def member_count
    @member_count ||= members.count
  end

  def pending_invitations_count
    @pending_invitations_count ||= family_invitations.active.count
  end

  def owners
    members.joins(:family_membership)
           .where(family_memberships: { role: :owner })
  end

  def owner
    @owner ||= creator
  end

  def full?
    (member_count + pending_invitations_count) >= MAX_MEMBERS
  end

  def active_invitations
    family_invitations.active.includes(:invited_by)
  end

  def clear_member_cache!
    @member_count = nil
    @pending_invitations_count = nil
    @owner = nil
  end
end
