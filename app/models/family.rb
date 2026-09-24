# frozen_string_literal: true

class Family < ApplicationRecord
  has_many :family_memberships, dependent: :destroy, class_name: 'Family::Membership'
  has_many :members, through: :family_memberships, source: :user
  has_many :family_invitations, dependent: :destroy, class_name: 'Family::Invitation'
  has_many :location_requests, dependent: :delete_all, class_name: 'Family::LocationRequest'
  belongs_to :creator, class_name: 'User'

  validates :name, presence: true, length: { maximum: 50 }

  MAX_MEMBERS = 5

  def access_live?
    return true if DawarichSettings.self_hosted?
    return access_until.future? if access_until

    owner_holds_plan?
  end

  # A live family subscription supplies its current period. After a downgrade,
  # retain already paid access but never extend it from a non-family renewal.
  # A callback without a date must not erase the previously recorded period.
  def refresh_access_until!(subscription_owner)
    return if DawarichSettings.self_hosted? || subscription_owner&.active_until.blank?

    period_end = if subscription_owner.family?
                   subscription_owner.active_until
                 elsif access_until
                   [access_until, subscription_owner.active_until].min
                 end
    update!(access_until: period_end) unless access_until == period_end
  end

  def can_add_members?
    return true if DawarichSettings.self_hosted?

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
    return false if DawarichSettings.self_hosted?

    (member_count + pending_invitations_count) >= MAX_MEMBERS
  end

  def active_invitations
    family_invitations.active.includes(:invited_by)
  end

  def owner_holds_plan?
    return false unless owner&.family?

    owner.active_until&.future? || false
  end

  def clear_member_cache!
    @member_count = nil
    @pending_invitations_count = nil
    @owner = nil
  end
end
